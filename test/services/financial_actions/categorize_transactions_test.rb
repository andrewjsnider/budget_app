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

  test "explicit categorization refuses to change reconciled history" do
    account = create(:account)
    original = create(:category, name: "Original")
    replacement = create(:category, name: "Replacement")
    reconciliation = create(:reconciliation, account: account)
    transaction = create(:transaction, account:, category: original, reconciliation:, reconciled_at: Time.current)

    result = FinancialActions::CategorizeTransactions.call(
      input: { "mappings" => [ { "transaction_id" => transaction.id, "category" => replacement.id } ] },
      dry_run: false
    )

    assert_equal 1, result[:failed]
    assert_equal "reconciled_transaction", result[:results].sole[:reason]
    assert_equal original, transaction.reload.category
  end
end
