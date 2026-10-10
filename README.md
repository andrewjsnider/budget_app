# Budget App

## Money conventions

Ledger transactions use signed integer cents. Inflows are positive, outflows are negative, and zero-value transactions are invalid. Account balances and reconciliation calculations sum those signed values directly.

Income estimates and recurring expenses are both entered and stored as positive magnitudes. Projection code adds income estimates and subtracts recurring expenses. This keeps the human-entered schedule forms consistent while preserving a single signed convention in the ledger.

Before converting a database created under the legacy unsigned-expense behavior, run `bin/rails budget:sign_preflight`. Review and resolve every blocker before running the separately confirmed normalization command documented by that task.

For the reviewed one-time development conversion, run `bin/normalize_signed_ledger`. It performs both preflights, creates and verifies a private PostgreSQL backup, applies migrations, requires the exact interactive phrase `NORMALIZE SIGNED LEDGER`, normalizes once, verifies the completion marker, and runs the test suite.

## Statement staging

Monthly statement CSVs are staged separately from ledger transactions. Source files stay beneath the private finance root, which defaults to `/Users/ajs/Private/finance` and can be configured with `BUDGET_FINANCE_ROOT`. Do not place source statements in this repository.

Set a stable statement import key on each active account from the account edit page before staging. Keys use lowercase letters, numbers, and hyphens (for example, `primary-checking`) and become immutable after the first statement import.

Preview a signed `Amount` CSV without database writes:

```sh
bin/rails statements:stage \
  ACCOUNT=primary-checking \
  FILE=/Users/ajs/Private/finance/2026-10/checking.csv \
  PARSER=generic_signed_csv \
  DRY_RUN=1
```

Remove `DRY_RUN=1` to persist a `StatementImport` and one `StatementEntry` per source row. Optional inputs are `STARTS_ON=YYYY-MM-DD`, `ENDS_ON=YYYY-MM-DD`, and a decimal-dollar `ENDING_BALANCE`. Add `JSON=1` for structured JSON output. Staging never creates or changes ledger `Transaction` records.

The exact source file is identified by its SHA-256 hash within an account. Each entry identity includes that file hash. An institution transaction ID is preferred when present; otherwise the identity uses a canonical representation of the complete source row. Both forms include a within-file occurrence ordinal, so identical purchases survive while an exact file rerun remains idempotent. Failed rows are retained with their source row number, raw header/value payload, error code, and message.

The browser CSV importer remains available as a legacy direct-ledger import and is not part of the statement-staging workflow.

## Statement matching and reconciliation

Statement parsing and resolution are separate lifecycles. A parsed entry begins as `unresolved` and may become `matched`, `new_transaction`, `ambiguous`, or `ignored`. Failed parser rows have no resolution state and always block reconciliation. Match, create, ambiguity, rejection, and ignore decisions are recorded in append-only `StatementEntryResolution` rows. Ignoring an entry requires a human-supplied reason.

Review an import without changing the database:

```sh
bin/rails statements:review IMPORT_ID=123 JSON=1
```

For a first reconciliation with no eligible starting-balance transaction, supply a decimal-dollar opening balance:

```sh
bin/rails statements:review IMPORT_ID=123 OPENING_BALANCE=1200.00 JSON=1
```

The matcher uses policy `statement-match-v1`. Candidates must have the same account, exact signed amount, a non-starting-balance ledger transaction, and a date within three days of the statement's posted or transaction date. Evidence reports the date difference, exact and normalized description results, and existing statement links. Merchant normalization is deterministic: it folds case and punctuation and removes a small documented set of card-processing words. It does not use fuzzy scoring or AI.

A match is automatic only when there is exactly one eligible candidate and it has either an exact date or a normalized-description match. Any additional eligible candidate makes the result ambiguous; ties are never broken silently. Apply those narrow automatic matches with:

```sh
bin/rails statements:apply_matches IMPORT_ID=123
```

This command never creates ledger transactions. Resolve the remaining entries explicitly:

```sh
bin/rails statements:match ENTRY_ID=456 TRANSACTION_ID=789 REASON="verified manually"
bin/rails statements:reject_candidate ENTRY_ID=456 TRANSACTION_ID=790 REASON="different purchase"
bin/rails statements:create_transaction ENTRY_ID=456
bin/rails statements:ignore ENTRY_ID=456 REASON="non-ledger informational row"
```

Creating a transaction preserves the statement's signed amount, uses `posted_on` before `transaction_on`, and uses the normalized description before the raw description. Active payee rules are evaluated in ascending database ID, matching the existing importer semantics. If no rule matches, expenses use `Uncategorized` and income uses `Imported Income`. Retrying an already completed create or match operation returns its existing result.

Final reconciliation is statement-membership based; it does not infer membership from every transaction in a date range. Its arithmetic is:

```text
computed ending balance = authoritative opening balance + linked signed statement activity
difference = statement ending balance - computed ending balance
```

The previous finalized reconciliation's statement ending balance is the authoritative opening. The first reconciliation requires `OPENING_BALANCE` or an existing starting-balance transaction. Finalization requires every row to be accounted for, a valid period and ending balance, valid same-account/same-amount links, no conflicting reconciliation or finalized period, and an exact zero-cent difference:

```sh
bin/rails statements:finalize IMPORT_ID=123 OPENING_BALANCE=1200.00
```

Finalization is transactional and idempotent. It finalizes one statement-backed reconciliation, assigns its linked transactions, and marks the statement import reviewed. Finalized transaction membership and reconciliation financial fields are immutable through the application models.

Rows from overlapping source files keep their independent Phase 2 provenance. A transaction linked by another import remains visible as a candidate and may be reused, so overlapping exports do not require duplicate ledger activity. A transaction can appear only once within any one import. Finalized statement periods may not overlap, and a transaction already owned by another finalized reconciliation blocks finalization. The application does not automatically supersede a partial export: review the later full-period file explicitly and keep or mark the partial import `superseded` only after deciding which statement is authoritative.

The existing browser reconciliation screen is labeled legacy. It remains available for historical/manual date-range records, while new staged statements use the statement-backed commands above.

## Monthly processing boundary

Each private month directory must contain `manifest.yml`; account identity is never inferred from filenames. A minimal manifest is:

```yaml
month: 2026-10
statements:
  - account: primary-checking
    file: statements/checking.csv
    parser: generic_signed_csv
    starts_on: 2026-10-01
    ends_on: 2026-10-31
    ending_balance: "4812.37"
```

Preview October without database writes:

```sh
bin/rails budget:process_month MONTH=2026-10 DRY_RUN=1 JSON=1
```

The default source is `/Users/ajs/Private/finance/2026-10`; the default output is its `output` directory. Override them with `SOURCE_DIR` and `OUTPUT_DIR`. Both directories must remain outside this repository.

After reviewing the preview, omit `DRY_RUN=1` to stage new imports and persist an auditable `MonthlyProcessingRun`. Apply mode still does not match ambiguous entries, create or ignore transactions, or finalize reconciliation. Each invocation writes a new private `output/runs/<run-name>/` bundle containing `process_run.json`, `statements.json`, `unresolved_items.json`, `reconciliation_summary.json`, and `reconciliation_summary.md`.

The local Paperclip boundary and prohibitions are documented in [docs/paperclip_personal_finance_agent.md](docs/paperclip_personal_finance_agent.md). Paperclip reads the generated bundle; it does not receive database credentials or authority to mutate financial records.

## Approved Paperclip financial actions

Paperclip may inspect and invoke only the deterministic commands below. Each mutation command accepts a reviewed JSON object through `INPUT`; keep these files under `Rails.root/private/` or in the external private finance directory. Use `DRY_RUN=1 JSON=1` first. Rails resolves exact IDs or names, validates signs and accounts, refuses ambiguous references, and protects reconciled financial facts. Rails console and direct SQL remain prohibited.

**Reconciliation freezes financial facts, not categorization metadata.** Reviewed categorization may change a reconciled transaction's category, including through an explicitly applied existing payee rule. Amount, date, account, sign, cleared/reconciliation state, statement linkage, and deletion remain protected. The structured categorization result records the prior and new category, evidence source, policy version, and whether the transaction was reconciled.

Categorize explicit transactions or apply active payee rules to an explicit transaction list:

```json
{
  "mappings": [{"transaction_id": 123, "category": "Groceries"}],
  "apply_payee_rules": true,
  "transaction_ids": [124, 125]
}
```

```sh
bin/rails budget:categorize INPUT=private/actions/categorize.json DRY_RUN=1 JSON=1
```

Create or update payee rules. Apply mode always requires the reviewed confirmation token:

```json
{"rules": [{"pattern": "CITY WATER", "match_type": "contains", "category": "Utilities", "active": true}]}
```

```sh
bin/rails budget:manage_payee_rules INPUT=private/actions/payee_rules.json DRY_RUN=1 JSON=1
CONFIRM=apply-payee-rules-v1 bin/rails budget:manage_payee_rules INPUT=private/actions/payee_rules.json JSON=1
```

Classify exact transaction pairs as `internal_transfer`, `savings_transfer`, or `credit_card_payment`. Exact opposite amounts, different owned accounts, and dates within three days are required. Single positive inflows may be classified as `refund`, `reimbursement`, or `windfall`:

```json
{"classifications": [{"kind": "savings_transfer", "transaction_ids": [201, 202], "evidence": {"reviewed_by": "owner"}}]}
```

```sh
bin/rails budget:classify_transactions INPUT=private/actions/classifications.json DRY_RUN=1 JSON=1
```

Reviewed classifications are stored as separate auditable metadata and may be added to reconciled transactions when all classification validations pass. They never rewrite the underlying transactions or reconciliation records.

Record recurring expenses as positive magnitudes with type `subscription`, `utility`, `insurance`, `debt`, `essential`, `discretionary`, or `other`:

```json
{"recurring_expenses": [{"name": "Electric Company", "account": "primary-checking", "category": "Electric", "expense_type": "utility", "cadence": "monthly", "interval": 1, "day_of_month": 15, "estimated_amount_cents": 12500, "start_on": "2026-01-01", "active": true}]}
```

```sh
bin/rails budget:manage_recurring_expenses INPUT=private/actions/recurring.json DRY_RUN=1 JSON=1
```

Build a next-month proposal. Apply mode persists only an idempotent `draft`; it never creates or approves a `BudgetMonth`:

```sh
bin/rails budget:propose_budget MONTH=2026-11 DRY_RUN=1 JSON=1
bin/rails budget:propose_budget MONTH=2026-11 JSON=1
```

Transfer classifications leave ledger transactions intact but exclude them from budget income and expense analytics. Expense-category refunds remain included as positive offsets to spending. Reimbursements and windfalls remain explicitly distinguishable, and windfalls are excluded from the recurring-income history used alongside scheduled recurring income.

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
