require "test_helper"

class TransactionsTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user)
    sign_in(@user)

    @account = FactoryBot.create(:account, name: "Checking", kind: "asset", archived: false)
    @category = FactoryBot.create(:category, name: "Groceries", kind: "expense", group: "food", archived: false)
  end

  def test_index_renders
    get transactions_path(month: "2026-02")
    assert_response :success
    assert_includes response.body, "Transactions"
  end

  def test_create_transaction
    assert_difference -> { Transaction.count }, 1 do
      post transactions_path, params: {
        transaction: {
          occurred_on: "2026-02-03",
          description: "Test",
          amount_cents: -1234,
          account_id: @account.id,
          category_id: @category.id
        }
      }
    end

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Test"
  end
end
