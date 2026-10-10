require "test_helper"

class ReconciliationFlowTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user)
  end

  def test_reconciliation_finalizes_only_when_balanced_exactly
    sign_in @user

    account = create(:account, name: "Checking")
    income = create(:category, name: "Opening", kind: "income", group: "income", archived: false)
    expense = create(:category, name: "Electric", kind: "expense", group: "utilities", archived: false)
    month = Date.new(2026, 2, 1)

    Transaction.create!(occurred_on: month - 1.day, description: "Starting", amount_cents: 100_00, account: account, category: income, starting_balance: true)
    bill = Transaction.create!(occurred_on: month + 4.days, description: "Bill", amount_cents: -30_00, account: account, category: expense)

    post account_reconciliations_path(account), params: {
      starts_on: "2026-02-01",
      ends_on: "2026-02-28",
      statement_ending_balance: "70.00",
      cleared_transaction_ids: [ bill.id ]
    }

    reconciliation = account.reconciliations.order(:id).last
    assert_redirected_to account_reconciliation_path(account, reconciliation)
    assert_equal "finalized", reconciliation.status
    assert_equal 0, reconciliation.difference_cents
    assert_not_nil reconciliation.reconciled_at
    assert_equal reconciliation.id, bill.reload.reconciliation_id
  end

  def test_imbalance_creates_an_explicit_draft_and_does_not_reconcile_transactions
    sign_in @user

    account = create(:account, name: "Checking")
    expense = create(:category, kind: "expense")
    month = Date.new(2026, 3, 1)
    bill = create(:transaction, account: account, category: expense, occurred_on: month + 2.days, amount_cents: -30_00)

    post account_reconciliations_path(account), params: {
      starts_on: month.to_s,
      ends_on: month.end_of_month.to_s,
      statement_ending_balance: "-29.99",
      cleared_transaction_ids: [ bill.id ]
    }

    reconciliation = account.reconciliations.order(:id).last
    assert_equal "draft", reconciliation.status
    assert_equal 1, reconciliation.difference_cents
    assert_nil reconciliation.reconciled_at
    assert_nil bill.reload.reconciliation_id
    assert_nil bill.reconciled_at
  end
end
