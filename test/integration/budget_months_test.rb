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
    assert_select "section[aria-label='Budget summary']" do
      assert_includes response.body, "Budgeted"
      assert_includes response.body, "Spent"
      assert_includes response.body, "Remaining"
      assert_includes response.body, "Planned savings"
    end
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
      amount_cents: -2_500,
      category: category,
      account: account,
      cleared: true
    )

    get budget_month_path(month: "2026-02")
    assert_response :success

    assert_includes body, category.name
    assert_includes body, "Utilities"
    assert_includes body, "$100.00"
    assert_includes body, "$25.00"
    assert_includes body, "$75.00"
  end

  def test_budget_page_sorts_each_meaningful_column_in_both_directions
    sign_in @user
    month = Date.new(2026, 2, 1)
    account = create(:account)
    alpha = create(:category, name: "Alpha", kind: "expense", group: "Zulu Group", archived: false)
    zulu = create(:category, name: "Zulu", kind: "expense", group: "Alpha Group", archived: false)
    budget_month = BudgetMonth.create!(month: month)
    budget_month.budget_items.create!(category: alpha, assigned_cents: 10_000)
    budget_month.budget_items.create!(category: zulu, assigned_cents: 20_000)
    create(:transaction, occurred_on: month + 1, amount_cents: -3_000, category: alpha, account: account)
    create(:transaction, occurred_on: month + 1, amount_cents: -1_000, category: zulu, account: account)

    expected_ascending = {
      "category" => %w[Alpha Zulu],
      "group" => %w[Zulu Alpha],
      "assigned" => %w[Alpha Zulu],
      "activity" => %w[Zulu Alpha],
      "available" => %w[Alpha Zulu]
    }

    expected_ascending.each do |sort_key, expected|
      get budget_month_path(month: "2026-02", sort: sort_key, direction: "asc")
      assert_equal expected, rendered_category_names, "expected #{sort_key} ascending"

      get budget_month_path(month: "2026-02", sort: sort_key, direction: "desc")
      assert_equal expected.reverse, rendered_category_names, "expected #{sort_key} descending"
    end
  end

  def test_budget_sort_headers_toggle_and_month_form_preserves_sort
    sign_in @user
    create(:category, name: "Electric", kind: "expense", group: "utilities", archived: false)

    get budget_month_path(month: "2026-02", sort: "assigned", direction: "desc")

    assert_response :success
    assert_select "th[aria-sort='descending'] a", text: /Budgeted/ do |links|
      assert_includes links.first["href"], "sort=assigned"
      assert_includes links.first["href"], "direction=asc"
    end
    assert_select "form[method='get'] input[name='sort'][value='assigned']"
    assert_select "form[method='get'] input[name='direction'][value='desc']"
  end

  def test_budget_default_and_unsupported_sort_keep_existing_group_name_order
    sign_in @user
    create(:category, name: "Alpha", kind: "expense", group: "Zulu Group", archived: false)
    create(:category, name: "Zulu", kind: "expense", group: "Alpha Group", archived: false)

    get budget_month_path(month: "2026-02")
    assert_equal %w[Zulu Alpha], rendered_category_names

    get budget_month_path(month: "2026-02", sort: "unsafe", direction: "sideways")
    assert_equal %w[Zulu Alpha], rendered_category_names
  end

  private

  def rendered_category_names
    response.parsed_body.css("tbody tr").map { |row| row.css("td").first.text.strip }
  end
end
