require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  def setup
    @account  = FactoryBot.create(:account)
    @category = FactoryBot.create(:category)
  end

  def test_allows_only_one_starting_balance_per_account
    FactoryBot.create(
      :transaction,
      account: @account,
      category: @category,
      starting_balance: true
    )

    tx2 = FactoryBot.build(
      :transaction,
      account: @account,
      category: @category,
      starting_balance: true
    )

    assert_not tx2.valid?
    assert_includes tx2.errors[:starting_balance], "already exists for this account"
  end
end
