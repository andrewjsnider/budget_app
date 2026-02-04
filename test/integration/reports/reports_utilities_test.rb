require "test_helper"

class ReportsUtilitiesTest < ActionDispatch::IntegrationTest
  def test_utilities_report_renders_and_shows_totals
    user = create(:user, password: "password123", password_confirmation: "password123")
    sign_in(user)

    electric = create(:category, name: "Electric", kind: "expense", group: "utilities", archived: false)
    water = create(:category, name: "Water", kind: "expense", group: "utilities", archived: false)

    Transaction.create!(occurred_on: Date.new(2026, 2, 5), description: "Electric bill", amount_cents: -123_45, account_name: "Checking", category: electric)
    Transaction.create!(occurred_on: Date.new(2026, 2, 10), description: "Water bill", amount_cents: -67_89, account_name: "Checking", category: water)

    get reports_utilities_path(from: "2026-02", to: "2026-02")
    assert_response :success
    assert_includes response.body, "Utilities"
    assert_includes response.body, "$123.45"
    assert_includes response.body, "$67.89"
  end
end
