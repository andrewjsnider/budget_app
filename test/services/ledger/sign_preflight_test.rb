require "test_helper"

class LedgerSignPreflightTest < ActiveSupport::TestCase
  def test_reports_changes_without_mutating_data
    account = create(:account)
    expense = create(:category, kind: "expense")
    transaction = create(:transaction, account: account, category: expense, amount_cents: 25_00)
    recurring = create(:recurring_expense, account: account, category: expense, estimated_amount_cents: 10_00)
    recurring.update_columns(estimated_amount_cents: -10_00)

    report = Ledger::SignPreflight.call

    assert report[:safe_to_normalize]
    assert_equal [ { id: transaction.id, from_cents: 25_00, to_cents: -25_00 } ], report.dig(:planned_changes, :transactions)
    assert_equal [ { id: recurring.id, from_cents: -10_00, to_cents: 10_00 } ], report.dig(:planned_changes, :recurring_expenses)
    assert_equal 25_00, transaction.reload.amount_cents
    assert_equal(-10_00, recurring.reload.estimated_amount_cents)
  end

  def test_reports_ambiguous_credit_starting_balance
    account = create(:account, kind: "credit")
    category = create(:category, kind: "expense")
    transaction = create(:transaction, account: account, category: category, amount_cents: 50_00, starting_balance: true)

    report = Ledger::SignPreflight.call

    assert_not report[:safe_to_normalize]
    assert report[:ambiguous_records].any? { |item| item[:id] == transaction.id }
  end
end
