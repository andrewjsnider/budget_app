require "test_helper"

class ProjectionReportTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user)
  end

  def test_projection_includes_recurring_expense
    sign_in @user

    account = create(:account, name: "Checking")
    income_cat = create(:category, name: "Income", kind: "income", group: "income", archived: false)
    util_cat = create(:category, name: "Sewer", kind: "expense", group: "utilities", archived: false)

    Transaction.create!(occurred_on: Date.new(2026, 2, 1), description: "Starting", amount_cents: 100_00, account: account, account_name: "Checking", category: income_cat)
    RecurringExpense.create!(name: "Sewer", account: account, category: util_cat, cadence: "monthly", interval: 1, day_of_month: 15, estimated_amount_cents: -50_00, start_on: Date.new(2026, 2, 1), active: true)

    get reports_projection_path(account, from: "2026-02-01", to: "2026-02-20")
    assert_response :success
    assert_includes response.body, "Projection"
  end
end
