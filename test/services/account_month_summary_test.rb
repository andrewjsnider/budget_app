require "test_helper"

class AccountMonthSummaryTest < ActiveSupport::TestCase
  def test_opening_activity_and_ending_use_signed_ledger_amounts
    account = create(:account)
    income = create(:category, kind: "income")
    expense = create(:category, kind: "expense")
    month = Date.new(2026, 6, 1)

    create(:transaction, account: account, category: income, occurred_on: month - 1.day, amount_cents: 100_00)
    create(:transaction, account: account, category: income, occurred_on: month + 1.day, amount_cents: 50_00)
    create(:transaction, account: account, category: expense, occurred_on: month + 2.days, amount_cents: -20_00)

    summary = AccountMonthSummary.new(account: account, month: month)

    assert_equal 100_00, summary.opening_balance_cents
    assert_equal 30_00, summary.activity_cents
    assert_equal 130_00, summary.ending_balance_cents
  end
end
