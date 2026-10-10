require "test_helper"

class StatementEntriesResolutionTest < ActiveSupport::TestCase
  def setup
    @account = create(:account)
    @statement_import = create(:statement_import, account: @account)
    @entry = create(
      :statement_entry,
      statement_import: @statement_import,
      posted_on: Date.new(2026, 10, 8),
      normalized_description: "LOCAL MARKET",
      amount_cents: -3_425
    )
  end

  test "manual match links a same-account same-amount transaction and audits the decision" do
    transaction = create(
      :transaction,
      account: @account,
      occurred_on: Date.new(2026, 10, 7),
      amount_cents: -3_425
    )

    StatementEntries::MatchExisting.call(entry: @entry, transaction: transaction, reason: "reviewed receipt")

    assert_equal "matched", @entry.reload.resolution_status
    assert_equal transaction, @entry.ledger_transaction
    audit = @entry.statement_entry_resolutions.sole
    assert_equal "matched_existing", audit.action
    assert_equal "human", audit.decision_source
    assert_equal "reviewed receipt", audit.reason
  end

  test "new transaction creation preserves sign and does not duplicate on retry" do
    transaction = nil
    assert_difference "Transaction.count", 1 do
      transaction = StatementEntries::CreateTransaction.call(entry: @entry)
      assert_equal transaction, StatementEntries::CreateTransaction.call(entry: @entry)
    end

    assert_equal(-3_425, transaction.amount_cents)
    assert_equal Date.new(2026, 10, 8), transaction.occurred_on
    assert_equal @account, transaction.account
    assert_equal "Uncategorized", transaction.category.name
    assert_equal "new_transaction", @entry.reload.resolution_status
    assert_equal 1, @entry.statement_entry_resolutions.where(action: "created_transaction").count
  end

  test "new transaction uses the first matching active payee rule by id" do
    first_category = create(:category, name: "Food")
    second_category = create(:category, name: "Other")
    first_rule = create(:payee_rule, category: first_category, pattern: "market", match_type: "contains")
    create(:payee_rule, category: second_category, pattern: "local", match_type: "contains")

    transaction = StatementEntries::CreateTransaction.call(entry: @entry)

    assert_equal first_category, transaction.category
    assert_equal first_rule.id, @entry.statement_entry_resolutions.sole.evidence.fetch("payee_rule_id")
  end

  test "candidate rejection is audited and removes that candidate from later reviews" do
    transaction = create(:transaction, account: @account, occurred_on: @entry.posted_on, amount_cents: @entry.amount_cents)

    StatementEntries::RejectCandidate.call(entry: @entry, transaction: transaction, reason: "different purchase")
    result = StatementEntries::Matcher.call(entry: @entry)

    assert_equal "no_candidate", result.fetch(:classification)
    assert_empty result.fetch(:candidates)
    resolution = @entry.statement_entry_resolutions.sole
    assert_equal "candidate_rejected", resolution.action
    assert_equal "different purchase", resolution.reason
  end

  test "ignore requires a reason and persists an auditable decision" do
    assert_raises(StatementEntries::Ignore::InvalidIgnore) do
      StatementEntries::Ignore.call(entry: @entry, reason: " ")
    end

    StatementEntries::Ignore.call(entry: @entry, reason: "Bank informational row")

    assert_equal "ignored", @entry.reload.resolution_status
    assert_equal "Bank informational row", @entry.ignored_reason
    resolution = @entry.statement_entry_resolutions.sole
    assert_equal "ignored", resolution.action
    assert_not resolution.update(reason: "rewritten")
    assert_not resolution.destroy
    assert_equal "Bank informational row", resolution.reload.reason
  end

  test "safe batch apply matches only definite candidates and marks ties ambiguous" do
    exact_transaction = create(
      :transaction,
      account: @account,
      occurred_on: @entry.posted_on,
      amount_cents: @entry.amount_cents
    )
    ambiguous_entry = create(
      :statement_entry,
      statement_import: @statement_import,
      posted_on: Date.new(2026, 10, 9),
      amount_cents: -1_200
    )
    2.times do |number|
      create(
        :transaction,
        account: @account,
        occurred_on: ambiguous_entry.posted_on,
        description: "Candidate #{number}",
        amount_cents: ambiguous_entry.amount_cents
      )
    end

    assert_no_difference "Transaction.count" do
      result = Statements::ApplyMatches.call(statement_import: @statement_import)
      assert_equal({ matched: 1, ambiguous: 1 }, result)
    end

    assert_equal exact_transaction, @entry.reload.ledger_transaction
    assert_equal "matched", @entry.resolution_status
    assert_equal "automatic", @entry.statement_entry_resolutions.sole.decision_source
    assert_equal "ambiguous", ambiguous_entry.reload.resolution_status
    assert_equal "marked_ambiguous", ambiguous_entry.statement_entry_resolutions.sole.action
  end
end
