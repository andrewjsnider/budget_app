require "test_helper"

class ReconciliationFlowTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user)
  end

  def test_can_reconcile_when_balanced
    sign_in @user

    account = create(:account, name: "Checking")
    cat = create(:category, name: "Electric", kind: "expense", group: "utilities", archived: false)

    Transaction.create!(occurred_on: Date.new(2026, 2, 5), description: "Bill", amount_cents: -100_00, account: account, account_name: "Checking", category: cat)

    post account_reconciliations_path(account), params: {
      starts_on: "2026-02-01",
      ends_on: "2026-02-28",
      statement_ending_balance: "-100.00",
      cleared_transaction_ids: [Transaction.last.id]
    }

    assert_response :redirect
  end
end
