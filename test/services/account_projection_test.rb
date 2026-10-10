require "test_helper"

class AccountProjectionTest < ActiveSupport::TestCase
  def test_starting_balance_uses_last_reconciled_ending_balance
    account = FactoryBot.create(:account)

    FactoryBot.create(
      :reconciliation,
      account: account,
      starts_on: Date.new(2026, 1, 1),
      ends_on: Date.new(2026, 1, 31),
      statement_ending_balance_cents: 10_000,
      reconciled_at: Time.current
    )

    FactoryBot.create(
      :transaction,
      account: account,
      occurred_on: Date.new(2026, 2, 1),
      amount_cents: 500,
      description: "Interest"
    )

    projection = AccountProjection.new(
      account: account,
      from: Date.new(2026, 2, 2),
      to: Date.new(2026, 2, 10)
    )

    assert_equal 10_500, projection.starting_balance_cents
  end

  def test_income_increases_and_recurring_expense_decreases_projection
    account = FactoryBot.create(:account)
    income_category = FactoryBot.create(:category, kind: "income")
    expense_category = FactoryBot.create(:category, kind: "expense")
    source = FactoryBot.create(:income_source, account: account, category: income_category)
    from = Date.new(2026, 5, 1)

    FactoryBot.create(
      :income_estimate,
      income_source: source,
      cadence: "monthly",
      day_of_month: 5,
      estimated_amount_cents: 200_00,
      start_on: from
    )
    FactoryBot.create(
      :recurring_expense,
      account: account,
      category: expense_category,
      cadence: "monthly",
      day_of_month: 10,
      estimated_amount_cents: 75_00,
      start_on: from
    )

    projection = AccountProjection.new(account: account, from: from, to: from.end_of_month)

    assert_equal 125_00, projection.daily_balances[from.end_of_month]
  end
end
