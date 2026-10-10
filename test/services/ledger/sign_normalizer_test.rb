require "test_helper"

class LedgerSignNormalizerTest < ActiveSupport::TestCase
  def test_normalization_is_explicit_transactional_and_idempotent
    account = create(:account)
    expense = create(:category, kind: "expense")
    transaction = create(
      :transaction,
      account: account,
      category: expense,
      occurred_on: Date.new(2026, 7, 5),
      description: "Market",
      amount_cents: 25_00
    )
    transaction.update_columns(
      import_hash: Transactions::ImportFingerprint.call(
        account_id: account.id,
        occurred_on: transaction.occurred_on,
        description: transaction.description,
        amount_cents: transaction.amount_cents
      )
    )
    recurring = create(:recurring_expense, account: account, category: expense, estimated_amount_cents: 10_00)
    recurring.update_columns(estimated_amount_cents: -10_00)

    result = Ledger::SignNormalizer.call(confirm: Ledger::SignNormalizer::CONFIRMATION)

    assert_equal :completed, result[:status]
    assert_equal(-25_00, transaction.reload.amount_cents)
    assert_equal 10_00, recurring.reload.estimated_amount_cents
    assert LedgerNormalization.exists?(key: LedgerNormalization::SIGNED_LEDGER_V1)

    csv = <<~CSV
      Date,Description,Amount
      2026-07-05,Market,-25.00
    CSV
    reimport = Transactions::CsvImport.call(account: account, csv_text: csv, default_category: expense)
    assert_equal 0, reimport[:imported]
    assert_equal 1, reimport[:skipped]

    second_result = Ledger::SignNormalizer.call(confirm: Ledger::SignNormalizer::CONFIRMATION)
    assert_equal :already_completed, second_result[:status]
    assert_empty second_result[:changes]
    assert_equal(-25_00, transaction.reload.amount_cents)
  end

  def test_normalization_requires_exact_confirmation
    assert_raises(Ledger::SignNormalizer::ConfirmationRequired) do
      Ledger::SignNormalizer.call(confirm: "yes")
    end
  end
end
