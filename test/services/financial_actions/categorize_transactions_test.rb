require "test_helper"

class FinancialActions::CategorizeTransactionsTest < ActiveSupport::TestCase
  test "dry run applies a deterministic payee rule without writing" do
    account = create(:account)
    original = create(:category, name: "Uncategorized")
    groceries = create(:category, name: "Groceries")
    transaction = create(:transaction, account:, category: original, description: "LOCAL MARKET", amount_cents: -2500)
    rule = create(:payee_rule, pattern: "LOCAL MARKET", category: groceries)

    result = FinancialActions::CategorizeTransactions.call(
      input: { "apply_payee_rules" => true, "transaction_ids" => [ transaction.id ] },
      dry_run: true
    )

    assert_equal 1, result[:categorized]
    assert_equal 0, result[:ambiguous]
    assert_equal [ rule.id ], result[:results].sole.dig(:evidence, :payee_rule_ids)
    assert_equal original, transaction.reload.category
  end

  test "explicit categorization changes reconciled metadata without changing ledger facts" do
    account = create(:account)
    original = create(:category, name: "Original")
    replacement = create(:category, name: "Replacement")
    reconciliation = create(:reconciliation, account: account)
    transaction = create(
      :transaction,
      account:,
      category: original,
      reconciliation:,
      reconciled_at: reconciliation.reconciled_at,
      occurred_on: Date.new(2026, 9, 12),
      amount_cents: -12_345,
      cleared: true,
      import_hash: "original-import"
    )
    statement_entry = create(
      :statement_entry,
      statement_import: create(:statement_import, account:, status: "reviewed"),
      ledger_transaction: transaction,
      resolution_status: "matched",
      resolved_at: Time.current
    )
    ledger_facts = transaction.attributes.slice(*Transaction::PROTECTED_RECONCILED_FIELDS)
    reconciliation_facts = reconciliation.attributes

    result = FinancialActions::CategorizeTransactions.call(
      input: { "mappings" => [ { "transaction_id" => transaction.id, "category" => replacement.id } ] },
      dry_run: false
    )

    assert_equal "categorize-transactions-v2", result[:policy_version]
    assert_equal 1, result[:categorized]
    assert result[:results].sole[:reconciled]
    assert_equal({ source: "explicit_mapping" }, result[:results].sole[:evidence])
    assert_equal replacement, transaction.reload.category
    assert_equal ledger_facts, transaction.attributes.slice(*Transaction::PROTECTED_RECONCILED_FIELDS)
    assert_equal [ statement_entry.id ], transaction.statement_entries.ids
    assert_equal reconciliation_facts, reconciliation.reload.attributes
  end

  test "dry run does not persist a reconciled category change" do
    original = create(:category, name: "Original")
    replacement = create(:category, name: "Replacement")
    transaction = create(:transaction, category: original, reconciled_at: Time.current)

    result = FinancialActions::CategorizeTransactions.call(
      input: { "mappings" => [ { "transaction_id" => transaction.id, "category" => replacement.id } ] },
      dry_run: true
    )

    assert_equal 1, result[:categorized]
    assert_equal "would_categorize", result[:results].sole[:reason]
    assert result[:results].sole[:reconciled]
    assert_equal original, transaction.reload.category
  end

  test "explicit payee rule application categorizes a reconciled transaction" do
    original = create(:category, name: "Uncategorized")
    replacement = create(:category, name: "Utilities")
    transaction = create(:transaction, category: original, description: "CITY WATER PAYMENT", reconciled_at: Time.current)
    rule = create(:payee_rule, pattern: "CITY WATER", category: replacement)

    result = FinancialActions::CategorizeTransactions.call(
      input: { "apply_payee_rules" => true, "transaction_ids" => [ transaction.id ] },
      dry_run: false
    )

    assert_equal 1, result[:categorized]
    assert_equal [ rule.id ], result[:results].sole.dig(:evidence, :payee_rule_ids)
    assert_equal replacement, transaction.reload.category
  end

  test "invalid and ambiguous categories remain blocked for reconciled transactions" do
    original = create(:category, name: "Original")
    first = create(:category, name: "First")
    second = create(:category, name: "Second")
    transaction = create(:transaction, category: original, reconciled_at: Time.current)

    ambiguous = FinancialActions::CategorizeTransactions.call(
      input: {
        "mappings" => [
          { "transaction_id" => transaction.id, "category" => first.id },
          { "transaction_id" => transaction.id, "category" => second.id }
        ]
      },
      dry_run: false
    )
    invalid = FinancialActions::CategorizeTransactions.call(
      input: { "mappings" => [ { "transaction_id" => transaction.id, "category" => "Missing category" } ] },
      dry_run: false
    )

    assert_equal 1, ambiguous[:ambiguous]
    assert_equal "conflicting_explicit_mappings", ambiguous[:results].sole[:reason]
    assert_equal 1, invalid[:failed]
    assert_includes invalid[:results].sole[:reason], "Category not found"
    assert_equal original, transaction.reload.category
  end
end
