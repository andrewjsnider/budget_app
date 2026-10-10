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

  def test_zero_amount_is_invalid
    transaction = FactoryBot.build(:transaction, amount_cents: 0)

    assert_not transaction.valid?
  end

  def test_reconciled_financial_fields_are_immutable
    transaction = FactoryBot.create(:transaction, reconciled_at: Time.current, import_hash: "original")
    replacement_account = FactoryBot.create(:account)

    assert_not transaction.update(amount_cents: transaction.amount_cents - 100)
    assert_includes transaction.errors[:base].join, "amount_cents"
    assert_not transaction.update(occurred_on: transaction.occurred_on + 1.day)
    assert_includes transaction.errors[:base].join, "occurred_on"
    assert_not transaction.update(account: replacement_account)
    assert_includes transaction.errors[:base].join, "account_id"
    assert_not transaction.update(import_hash: "replacement")
    assert_includes transaction.errors[:base].join, "import_hash"
    assert_not transaction.update(reconciled_at: nil)
    assert_includes transaction.errors[:base].join, "reconciled_at"
  end

  def test_reconciled_category_can_be_corrected_without_changing_financial_history
    transaction = FactoryBot.create(:transaction, reconciled_at: Time.current)
    replacement = FactoryBot.create(:category)

    assert transaction.update(category: replacement)
  end
end
