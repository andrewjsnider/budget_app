require "test_helper"

class TransactionsTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user)
    sign_in(@user)

    @account = FactoryBot.create(:account, name: "Checking", archived: false)
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

  def test_transactions_can_filter_by_category
    sign_in(@user)

    account = FactoryBot.create(:account)
    cat1 = FactoryBot.create(:category, name: "Power")
    cat2 = FactoryBot.create(:category, name: "Water")

    FactoryBot.create(:transaction, account: account, category: cat1, occurred_on: Date.new(2026, 2, 5), amount_cents: -1000, description: "Electric")
    FactoryBot.create(:transaction, account: account, category: cat2, occurred_on: Date.new(2026, 2, 6), amount_cents: -1000, description: "Water bill")

    get transactions_path(month: "2026-02", category_id: cat1.id)
    assert_response :success

    body = @response.body
    assert_includes body, "Electric"
    refute_includes body, "Water bill"
  end
end
