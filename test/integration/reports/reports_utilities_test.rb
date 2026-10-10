require "test_helper"

class ReportsUtilitiesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in(create(:user, password: "password123", password_confirmation: "password123"))
    @account = create(:account)
  end

  test "shows separate utility categories with correct signed monthly spending and zero months" do
    electric = create(:category, name: "Electric", kind: "expense", group: "utilities", archived: false)
    water = create(:category, name: "Water", kind: "expense", group: "utilities", archived: false)
    groceries = create(:category, name: "Groceries", kind: "expense", group: "food", archived: false)

    create(:transaction, occurred_on: Date.new(2026, 2, 5), amount_cents: -12_345, account: @account, category: electric)
    create(:transaction, occurred_on: Date.new(2026, 2, 6), amount_cents: 2_345, account: @account, category: electric)
    create(:transaction, occurred_on: Date.new(2026, 2, 10), amount_cents: -6_789, account: @account, category: water)
    create(:transaction, occurred_on: Date.new(2026, 2, 12), amount_cents: -99_999, account: @account, category: groceries)
    create(:transaction, occurred_on: Date.new(2026, 3, 5), amount_cents: -5_000, account: @account, category: electric)
    create_transfer(kind: "internal_transfer", amount_cents: 3_000, occurred_on: Date.new(2026, 2, 15), utility_category: electric, other_category: groceries)
    create_transfer(kind: "credit_card_payment", amount_cents: 4_000, occurred_on: Date.new(2026, 2, 20), utility_category: water, other_category: groceries)

    get reports_utilities_path(from: "2026-02", to: "2026-04")

    assert_response :success
    assert_select "thead th", text: "Electric"
    assert_select "thead th", text: "Water"
    refute_select "thead th", text: "Groceries"

    rows = rendered_rows
    assert_equal [ "$100.00", "$67.89", "$167.89" ], rows.fetch("2026-02")
    assert_equal [ "$50.00", "$0.00", "$50.00" ], rows.fetch("2026-03")
    assert_equal [ "$0.00", "$0.00", "$0.00" ], rows.fetch("2026-04")
    refute_includes response.body, "No utility categories found"
  end

  test "shows the empty state only when no utility categories exist" do
    create(:category, name: "Groceries", kind: "expense", group: "food", archived: false)

    get reports_utilities_path(from: "2026-02", to: "2026-02")

    assert_response :success
    assert_includes response.body, "No utility categories found"
  end

  test "shows zero spending instead of the empty state when a utility category has no transactions" do
    create(:category, name: "Sewer", kind: "expense", group: "utilities", archived: false)

    get reports_utilities_path(from: "2026-02", to: "2026-02")

    assert_response :success
    refute_includes response.body, "No utility categories found"
    assert_select "thead th", text: "Sewer"
    assert_equal [ "$0.00", "$0.00" ], rendered_rows.fetch("2026-02")
  end

  private

  def rendered_rows
    response.parsed_body.css("tbody tr").to_h do |row|
      cells = row.css("td").map { |cell| cell.text.strip }
      [ cells.shift, cells ]
    end
  end

  def create_transfer(kind:, amount_cents:, occurred_on:, utility_category:, other_category:)
    other_account = create(:account, kind: "savings")
    utility_leg = create(:transaction, account: @account, category: utility_category, occurred_on:, amount_cents: -amount_cents)
    other_leg = create(:transaction, account: other_account, category: other_category, occurred_on:, amount_cents: amount_cents)
    group_key = "#{kind}-#{utility_leg.id}-#{other_leg.id}"

    create(:transaction_classification, ledger_transaction: utility_leg, paired_transaction: other_leg, kind:, group_key:)
    create(:transaction_classification, ledger_transaction: other_leg, paired_transaction: utility_leg, kind:, group_key:)
  end
end
