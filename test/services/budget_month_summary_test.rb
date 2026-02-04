class BudgetMonthSummaryTest < ActiveSupport::TestCase
  def test_to_assign
    month = create(:budget_month)
    category = create(:category)

    Transaction.create!(occurred_on: month.month, amount_cents: 100_00, category:)
    BudgetItem.create!(budget_month: month, category:, assigned_cents: 100_00)

    summary = BudgetMonthSummary.new(month)
    assert_equal 0, summary.to_assign_cents
  end
end