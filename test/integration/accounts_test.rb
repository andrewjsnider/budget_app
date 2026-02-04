require "test_helper"

class AccountsTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user)
  end

  def test_accounts_index_and_show
    sign_in @user

    account = FactoryBot.create(:account, name: "Checking", archived: false)
    category = FactoryBot.create(:category, name: "Groceries")

    FactoryBot.create(
      :transaction,
      account: account,
      category: category,
      occurred_on: Date.current.beginning_of_month + 2.days,
      description: "Market",
      amount_cents: -1234
    )

    get accounts_path
    assert_response :success
    assert_includes @response.body, "Checking"

    get account_path(account, month: Date.current.strftime("%Y-%m"))
    assert_response :success
    assert_includes @response.body, "Market"
    assert_includes @response.body, "Groceries"
  end
end
