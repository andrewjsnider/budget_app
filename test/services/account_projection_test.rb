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
end
