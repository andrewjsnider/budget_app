require "test_helper"

class RecurringExpensesTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user)
    sign_in(@user)

    @account = FactoryBot.create(:account, name: "Checking", kind: "asset", archived: false)
    @category = FactoryBot.create(:category, name: "Sewer", kind: "expense", group: "utilities", archived: false)
  end

  def test_index_renders
    get recurring_expenses_path
    assert_response :success
    assert_includes response.body, "Recurring expenses"
  end

  def test_create_recurring_expense
    assert_difference -> { RecurringExpense.count }, 1 do
      post recurring_expenses_path, params: {
        recurring_expense: {
          name: "Sewer Bill",
          active: true,
          account_id: @account.id,
          category_id: @category.id,
          cadence: "monthly",
          interval: 1,
          day_of_month: 15,
          weekday: nil,
          estimated_amount_cents: -6800,
          start_on: "2026-02-01",
          end_on: nil
        }
      }
    end

    assert_redirected_to recurring_expenses_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Sewer Bill"
  end

  def test_update_recurring_expense
    recurring = RecurringExpense.create!(
      name: "Internet",
      active: true,
      account: @account,
      category: @category,
      cadence: "monthly",
      interval: 1,
      day_of_month: 1,
      estimated_amount_cents: -5000,
      start_on: Date.new(2026, 2, 1)
    )

    patch recurring_expense_path(recurring), params: {
      recurring_expense: {
        estimated_amount_cents: -7500,
        day_of_month: 20
      }
    }

    assert_redirected_to recurring_expenses_path
    recurring.reload
    assert_equal -7500, recurring.estimated_amount_cents
    assert_equal 20, recurring.day_of_month
  end
end
