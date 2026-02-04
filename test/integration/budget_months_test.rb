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
end
