require "test_helper"

class AccountTest < ActiveSupport::TestCase
  def test_valid_factory
    assert build(:account).valid?
  end

  def test_signed_transactions_determine_balance
    account = create(:account)
    income = create(:category, kind: "income")
    expense = create(:category, kind: "expense")
    opening_date = Date.new(2026, 4, 1)

    create(:transaction, account: account, category: income, occurred_on: opening_date, amount_cents: 100_00, starting_balance: true)
    create(:transaction, account: account, category: income, occurred_on: opening_date + 1.day, amount_cents: 50_00)
    create(:transaction, account: account, category: expense, occurred_on: opening_date + 2.days, amount_cents: -30_00)

    assert_equal 100_00, account.balance_cents(as_of: opening_date)
    assert_equal 120_00, account.balance_cents
  end
end
