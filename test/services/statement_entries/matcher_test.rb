require "test_helper"

class StatementEntriesMatcherTest < ActiveSupport::TestCase
  def setup
    @account = create(:account)
    @other_account = create(:account)
    @statement_import = create(:statement_import, account: @account)
    @entry = create(
      :statement_entry,
      statement_import: @statement_import,
      posted_on: Date.new(2026, 10, 6),
      normalized_description: "SAFEWAY #1234 TACOMA WA",
      amount_cents: -14_237
    )
    @category = create(:category)
  end

  test "exact amount and date produce one definite candidate" do
    transaction = ledger_transaction(occurred_on: Date.new(2026, 10, 6), description: "Safeway")

    result = StatementEntries::Matcher.call(entry: @entry)

    assert_equal "definite", result.fetch(:classification)
    assert_equal "match_existing", result.fetch(:recommended_action)
    assert_equal transaction.id, result.fetch(:candidates).sole.fetch(:transaction_id)
    assert result.fetch(:candidates).sole.dig(:evidence, :amount_exact)
    assert_equal 0, result.fetch(:candidates).sole.dig(:evidence, :date_delta_days)
  end

  test "no candidate recommends deliberate creation" do
    result = StatementEntries::Matcher.call(entry: @entry)

    assert_equal "no_candidate", result.fetch(:classification)
    assert_equal "create_new", result.fetch(:recommended_action)
    assert_empty result.fetch(:candidates)
  end

  test "multiple candidates are ambiguous and never silently tied" do
    ledger_transaction(occurred_on: Date.new(2026, 10, 6), description: "Safeway one")
    ledger_transaction(occurred_on: Date.new(2026, 10, 6), description: "Safeway two")

    result = StatementEntries::Matcher.call(entry: @entry)

    assert_equal "ambiguous", result.fetch(:classification)
    assert_equal "review_ambiguous", result.fetch(:recommended_action)
    assert_equal 2, result.fetch(:candidates).size
  end

  test "amount mismatch and wrong account never become candidates" do
    ledger_transaction(amount_cents: -14_238)
    ledger_transaction(account: @other_account)

    result = StatementEntries::Matcher.call(entry: @entry)

    assert_equal "no_candidate", result.fetch(:classification)
    assert_empty result.fetch(:candidates)
  end

  test "nearby date and normalized merchant text expose deterministic evidence" do
    transaction = ledger_transaction(
      occurred_on: Date.new(2026, 10, 5),
      description: "SAFEWAY 1234"
    )

    result = StatementEntries::Matcher.call(entry: @entry)
    candidate = result.fetch(:candidates).sole

    assert_equal "definite", result.fetch(:classification)
    assert_equal transaction.id, candidate.fetch(:transaction_id)
    assert_equal 1, candidate.dig(:evidence, :date_delta_days)
    assert_not candidate.dig(:evidence, :description_exact)
    assert candidate.dig(:evidence, :description_normalized_match)
  end

  test "a linked transaction is reusable by an overlapping export but not twice in one import" do
    transaction = ledger_transaction
    first_import = create(:statement_import, account: @account)
    first_entry = create(:statement_entry, statement_import: first_import, amount_cents: @entry.amount_cents)
    StatementEntries::MatchExisting.call(entry: first_entry, transaction: transaction)

    overlapping_result = StatementEntries::Matcher.call(entry: @entry)
    assert_equal "definite", overlapping_result.fetch(:classification)
    assert overlapping_result.fetch(:candidates).sole.dig(:evidence, :transaction_already_linked)
    assert_not overlapping_result.fetch(:candidates).sole.dig(:evidence, :same_import_link_conflict)

    duplicate_entry = create(
      :statement_entry,
      statement_import: @statement_import,
      posted_on: @entry.posted_on,
      amount_cents: @entry.amount_cents
    )
    StatementEntries::MatchExisting.call(entry: duplicate_entry, transaction: transaction)
    same_import_result = StatementEntries::Matcher.call(entry: @entry)

    assert_equal "no_candidate", same_import_result.fetch(:classification)
    assert same_import_result.fetch(:candidates).sole.dig(:evidence, :same_import_link_conflict)
  end

  private

  def ledger_transaction(account: @account, occurred_on: Date.new(2026, 10, 6), description: "SAFEWAY 1234", amount_cents: -14_237)
    create(
      :transaction,
      account: account,
      category: @category,
      occurred_on: occurred_on,
      description: description,
      amount_cents: amount_cents
    )
  end
end
