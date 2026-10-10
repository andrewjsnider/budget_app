require "test_helper"

class ReconciliationsFinalizeStatementTest < ActiveSupport::TestCase
  def setup
    @account = create(:account)
    @category = create(:category)
  end

  test "previous finalized statement ending balance is the authoritative next opening" do
    previous = create(
      :reconciliation,
      account: @account,
      starts_on: Date.new(2026, 9, 1),
      ends_on: Date.new(2026, 9, 30),
      statement_ending_balance_cents: 10_000,
      computed_ending_balance_cents: 10_000
    )
    statement_import, = resolved_import(activity_cents: -2_000, ending_balance_cents: 8_000)

    result = Statements::ReviewImport.call(statement_import: statement_import)

    assert_equal 10_000, result.fetch(:opening_balance_cents)
    assert_equal previous.id, result.fetch(:previous_reconciliation_id)
    assert_equal 8_000, result.fetch(:computed_ending_balance_cents)
    assert_equal 0, result.fetch(:difference_cents)
    assert result.fetch(:ready_to_finalize)
  end

  test "exact zero-cent difference finalizes atomically and protects membership" do
    statement_import, transaction = resolved_import(activity_cents: -2_000, ending_balance_cents: 8_000)

    result = Reconciliations::FinalizeStatement.call(
      statement_import: statement_import,
      opening_balance_cents: 10_000
    )

    reconciliation = Reconciliation.find(result.fetch(:reconciliation_id))
    assert_equal "finalized", reconciliation.status
    assert_equal 0, reconciliation.difference_cents
    assert_equal reconciliation, transaction.reload.reconciliation
    assert transaction.cleared?
    assert transaction.reconciled_at.present?
    assert_equal "reviewed", statement_import.reload.status

    transaction.amount_cents -= 1
    assert_not transaction.save
    assert_includes transaction.errors.full_messages.join, "reconciled financial fields"

    entry = statement_import.statement_entries.sole
    entry.amount_cents -= 1
    assert_not entry.save
    assert_includes entry.errors.full_messages.join, "cannot change after reconciliation"

    statement_import.statement_ending_balance_cents += 1
    assert_not statement_import.save
    assert_includes statement_import.errors.full_messages.join, "Reviewed statement fields cannot change"
  end

  test "one-cent difference cannot finalize and writes no partial state" do
    statement_import, transaction = resolved_import(activity_cents: -2_000, ending_balance_cents: 8_001)

    error = assert_raises(Reconciliations::FinalizeStatement::CannotFinalize) do
      Reconciliations::FinalizeStatement.call(
        statement_import: statement_import,
        opening_balance_cents: 10_000
      )
    end

    assert_includes error.review.fetch(:blockers).pluck(:code), "nonzero_difference"
    assert_equal 1, error.review.fetch(:difference_cents)
    assert_nil transaction.reload.reconciliation_id
    assert_equal "staged", statement_import.reload.status
    assert_nil statement_import.reconciliation
  end

  test "finalize is idempotent" do
    statement_import, = resolved_import(activity_cents: -2_000, ending_balance_cents: 8_000)

    first = Reconciliations::FinalizeStatement.call(
      statement_import: statement_import,
      opening_balance_cents: 10_000
    )
    second = nil
    assert_no_difference "Reconciliation.count" do
      second = Reconciliations::FinalizeStatement.call(
        statement_import: statement_import.reload,
        opening_balance_cents: 999_999
      )
    end

    assert_equal first.fetch(:reconciliation_id), second.fetch(:reconciliation_id)
    assert second.fetch(:already_finalized)
  end

  test "overlapping export reuses linked ledger activity but cannot create a competing reconciliation" do
    first_import, transaction = resolved_import(activity_cents: -2_000, ending_balance_cents: 8_000)
    Reconciliations::FinalizeStatement.call(
      statement_import: first_import,
      opening_balance_cents: 10_000
    )
    overlapping_import = create(
      :statement_import,
      account: @account,
      started_on: Date.new(2026, 10, 1),
      ended_on: Date.new(2026, 10, 31),
      statement_ending_balance_cents: 8_000
    )
    overlapping_entry = create(
      :statement_entry,
      statement_import: overlapping_import,
      posted_on: transaction.occurred_on,
      amount_cents: transaction.amount_cents
    )

    match_result = StatementEntries::Matcher.call(entry: overlapping_entry)
    assert_equal "definite", match_result.fetch(:classification)
    assert_no_difference "Transaction.count" do
      StatementEntries::MatchExisting.call(entry: overlapping_entry, transaction: transaction)
    end

    review = Statements::ReviewImport.call(statement_import: overlapping_import, opening_balance_cents: 10_000)
    blocker_codes = review.fetch(:blockers).pluck(:code)
    assert_includes blocker_codes, "transaction_already_reconciled"
    assert_includes blocker_codes, "overlapping_finalized_reconciliation"
    assert_not review.fetch(:ready_to_finalize)
  end

  private

  def resolved_import(activity_cents:, ending_balance_cents:)
    statement_import = create(
      :statement_import,
      account: @account,
      started_on: Date.new(2026, 10, 1),
      ended_on: Date.new(2026, 10, 31),
      statement_ending_balance_cents: ending_balance_cents
    )
    entry = create(
      :statement_entry,
      statement_import: statement_import,
      posted_on: Date.new(2026, 10, 5),
      normalized_description: "UTILITY PAYMENT",
      amount_cents: activity_cents
    )
    transaction = create(
      :transaction,
      account: @account,
      category: @category,
      occurred_on: entry.posted_on,
      description: "Utility payment",
      amount_cents: activity_cents
    )
    StatementEntries::MatchExisting.call(entry: entry, transaction: transaction)
    [ statement_import, transaction ]
  end
end
