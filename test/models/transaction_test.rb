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
    reconciliation = FactoryBot.create(:reconciliation, account: @account)
    transaction = FactoryBot.create(
      :transaction,
      account: @account,
      category: @category,
      reconciliation: reconciliation,
      reconciled_at: Time.current,
      cleared: true,
      import_hash: "original"
    )
    replacement_account = FactoryBot.create(:account)
    mutations = {
      amount_cents: -transaction.amount_cents,
      occurred_on: transaction.occurred_on + 1.day,
      account: replacement_account,
      import_hash: "replacement",
      starting_balance: true,
      cleared: false,
      reconciliation: nil,
      reconciled_at: nil
    }

    mutations.each do |attribute, value|
      candidate = transaction.reload
      assert_not candidate.update(attribute => value), "expected #{attribute} to remain immutable"
      protected_attribute = attribute == :account ? "account_id" : attribute == :reconciliation ? "reconciliation_id" : attribute.to_s
      assert_includes candidate.errors[:base].join, protected_attribute
    end
  end

  def test_reconciled_transaction_cannot_be_deleted
    transaction = FactoryBot.create(:transaction, reconciled_at: Time.current)

    assert_not transaction.destroy
    assert_includes transaction.errors[:base], "Cannot delete a reconciled transaction"
    assert Transaction.exists?(transaction.id)
  end

  def test_reconciled_category_can_be_corrected_without_changing_financial_history
    transaction = FactoryBot.create(:transaction, reconciled_at: Time.current)
    replacement = FactoryBot.create(:category)

    assert transaction.update(category: replacement)
  end
end
