require "test_helper"

class BudgetMonthsTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user)
  end

  def test_budget_month_show_renders
    sign_in @user

    create(:category, name: "Electric", kind: "expense", group: "utilities", archived: false)

    get budget_month_path(month: Date.current.strftime("%Y-%m"))
    assert_response :success
    assert_includes response.body, "To Assign"
    assert_includes response.body, "Electric"
  end

  def test_budget_month_update_saves_assigned
    sign_in @user

    cat = create(:category, name: "Sewer", kind: "expense", group: "utilities", archived: false)
    month = Date.current.beginning_of_month

    patch budget_month_path(month: month.strftime("%Y-%m")), params: { assigned: { cat.id.to_s => "50" } }
    assert_response :redirect

    budget_month = BudgetMonth.find_by!(month: month)
    item = budget_month.budget_items.find_by!(category_id: cat.id)
    assert_equal 5000, item.assigned_cents
  end

  def test_budget_month_activity_and_available
    sign_in(@user)

    category = FactoryBot.create(:category, kind: "expense", group: "Utilities", archived: false)
    account  = FactoryBot.create(:account)

    month = Date.new(2026, 2, 1)

    BudgetMonth.create!(month: month).tap do |bm|
      bm.budget_items.create!(category: category, assigned_cents: 10_000)
    end

    Transaction.create!(
      occurred_on: month + 9,
      description: "Electric",
      amount_cents: 2_500,
      category: category,
      account: account,
      cleared: true
    )

    get budget_month_path(month: "2026-02")
    assert_response :success

    assert_includes body, category.name
    assert_includes body, "Utilities"
    assert_includes body, "$100.00"
    assert_includes body, "-$25.00"
    assert_includes body, "$75.00"
  end
end
