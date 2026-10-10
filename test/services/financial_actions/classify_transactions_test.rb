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

  test "reviewed internal transfer classification adds metadata to reconciled transactions only" do
    checking = create(:account, kind: "checking")
    savings = create(:account, kind: "savings")
    expense = create(:category, kind: "expense")
    income = create(:category, kind: "income")
    transfer_out = create(
      :transaction,
      account: checking,
      category: expense,
      occurred_on: Date.new(2026, 9, 10),
      amount_cents: -20_000,
      cleared: true,
      reconciled_at: Time.current
    )
    transfer_in = create(
      :transaction,
      account: savings,
      category: income,
      occurred_on: Date.new(2026, 9, 11),
      amount_cents: 20_000,
      cleared: true,
      reconciled_at: Time.current
    )
    ledger_facts = [ transfer_out, transfer_in ].to_h do |transaction|
      [ transaction.id, transaction.attributes.slice(*Transaction::PROTECTED_RECONCILED_FIELDS) ]
    end

    result = FinancialActions::ClassifyTransactions.call(
      input: {
        "classifications" => [
          {
            "kind" => "internal_transfer",
            "transaction_ids" => [ transfer_out.id, transfer_in.id ],
            "source" => "paperclip",
            "evidence" => { "reviewed_by" => "owner" }
          }
        ]
      },
      dry_run: false
    )

    assert_equal 1, result[:classified]
    classifications = TransactionClassification.where(transaction_id: [ transfer_out.id, transfer_in.id ]).order(:transaction_id)
    assert_equal 2, classifications.size
    classifications.each do |classification|
      assert_equal "internal_transfer", classification.kind
      assert_equal "owner", classification.evidence.fetch("reviewed_by")
      assert_equal "transaction-classification-v1", classification.evidence.fetch("policy_version")
    end
    [ transfer_out, transfer_in ].each do |transaction|
      assert_equal ledger_facts.fetch(transaction.id), transaction.reload.attributes.slice(*Transaction::PROTECTED_RECONCILED_FIELDS)
    end
  end
end
