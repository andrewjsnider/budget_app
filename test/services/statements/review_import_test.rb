require "test_helper"

class StatementsReviewImportTest < ActiveSupport::TestCase
  def setup
    @account = create(:account)
  end

  test "failed, unresolved, and ambiguous entries are explicit blockers" do
    statement_import = create(:statement_import, account: @account, statement_ending_balance_cents: 0)
    create(:statement_entry, :failed, statement_import: statement_import)
    create(:statement_entry, statement_import: statement_import)
    create(:statement_entry, statement_import: statement_import, resolution_status: "ambiguous")

    result = Statements::ReviewImport.call(statement_import: statement_import, opening_balance_cents: 0)
    blocker_codes = result.fetch(:blockers).pluck(:code)

    assert_includes blocker_codes, "failed_entries"
    assert_includes blocker_codes, "unresolved_entries"
    assert_includes blocker_codes, "ambiguous_entries"
    assert_not result.fetch(:ready_to_finalize)
  end

  test "missing statement ending balance blocks finalization" do
    statement_import = create(:statement_import, account: @account, statement_ending_balance_cents: nil)

    result = Statements::ReviewImport.call(statement_import: statement_import, opening_balance_cents: 0)

    assert_includes result.fetch(:blockers).pluck(:code), "missing_ending_balance"
    assert_nil result.fetch(:difference_cents)
  end

  test "review exposes candidates but performs no writes" do
    statement_import = create(:statement_import, account: @account, statement_ending_balance_cents: 0)
    entry = create(:statement_entry, statement_import: statement_import)
    create(
      :transaction,
      account: @account,
      occurred_on: entry.posted_on,
      amount_cents: entry.amount_cents
    )
    before_attributes = entry.attributes

    assert_no_difference [ "Transaction.count", "StatementEntryResolution.count", "Reconciliation.count" ] do
      result = Statements::ReviewImport.call(statement_import: statement_import, opening_balance_cents: 0)
      assert_equal "match_existing", result.fetch(:entries).sole.fetch(:recommended_action)
    end

    assert_equal before_attributes, entry.reload.attributes
  end
end
