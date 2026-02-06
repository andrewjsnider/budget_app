class BudgetMonthSummaryTest < ActiveSupport::TestCase
  def test_to_assign
    month = create(:budget_month)
    category = create(:category)
    income_category = create(:category, kind: "income")
    expense_category = create(:category, kind: "expense")

    Transaction.create!(occurred_on: month.month, amount_cents: 100_00, category: income_category)
    Transaction.create!(occurred_on: month.month, amount_cents: 100_00, category: expense_category)

    BudgetItem.create!(budget_month: month, category:, assigned_cents: 100_00)

    summary = BudgetMonthSummary.new(month)
    assert_equal 0, summary.to_assign_cents
  end
end