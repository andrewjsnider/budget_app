require "test_helper"

class FinancialActions::ClassifyTransactionsTest < ActiveSupport::TestCase
  test "internal and savings transfers are auditable and excluded from income and spending" do
    month = Date.new(2026, 8, 1)
    checking = create(:account, kind: "checking")
    savings = create(:account, kind: "savings")
    cash = create(:account, kind: "cash")
    income = create(:category, kind: "income")
    expense = create(:category, kind: "expense")
    transfer_out = create(:transaction, account: checking, category: expense, occurred_on: month, amount_cents: -20_000)
    transfer_in = create(:transaction, account: savings, category: income, occurred_on: month + 1.day, amount_cents: 20_000)
    internal_out = create(:transaction, account: checking, category: expense, occurred_on: month + 2.days, amount_cents: -5000)
    internal_in = create(:transaction, account: cash, category: income, occurred_on: month + 2.days, amount_cents: 5000)

    result = FinancialActions::ClassifyTransactions.call(
      input: {
        "classifications" => [
          { "kind" => "savings_transfer", "transaction_ids" => [ transfer_out.id, transfer_in.id ] },
          { "kind" => "internal_transfer", "transaction_ids" => [ internal_out.id, internal_in.id ] }
        ]
      },
      dry_run: false
    )

    budget_month = create(:budget_month, month: month)
    rows = BudgetMonthCategoryRows.new(month:, expense_categories: [ expense ], assigned_by_category_id: {}).rows
    assert_equal 2, result[:classified]
    assert_equal 4, TransactionClassification.where(kind: TransactionClassification::TRANSFER_KINDS).count
    assert_equal 0, BudgetMonthSummary.new(budget_month).income_cents
    assert_equal 0, rows.sole.activity_cents
    assert_equal(-25_000, checking.transactions.sum(:amount_cents))
    assert_equal 20_000, savings.transactions.sum(:amount_cents)
    assert_equal 5000, cash.transactions.sum(:amount_cents)
  end

  test "refunds remain in expense analytics and offset spending" do
    month = Date.new(2026, 8, 1)
    account = create(:account)
    expense = create(:category, kind: "expense")
    create(:transaction, account:, category: expense, occurred_on: month, amount_cents: -10_000)
    refund = create(:transaction, account:, category: expense, occurred_on: month + 1.day, amount_cents: 2500)
    create(:transaction_classification, ledger_transaction: refund, kind: "refund")

    row = BudgetMonthCategoryRows.new(month:, expense_categories: [ expense ], assigned_by_category_id: {}).rows.sole

    assert_equal 7500, row.activity_cents
  end
end
