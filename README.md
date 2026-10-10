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
