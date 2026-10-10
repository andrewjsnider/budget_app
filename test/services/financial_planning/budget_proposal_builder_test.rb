require "test_helper"

class FinancialPlanning::BudgetProposalBuilderTest < ActiveSupport::TestCase
  test "proposal separates recurring and total income and excludes transfers and windfalls from baseline" do
    month = Date.new(2026, 11, 1)
    checking = create(:account, kind: "checking")
    savings = create(:account, kind: "savings")
    income = create(:category, name: "Pay", kind: "income")
    windfalls = create(:category, name: "Windfalls", kind: "income")
    expense = create(:category, name: "Living", kind: "expense")
    source = create(:income_source, account: checking, category: income, active: true)
    create(
      :income_estimate,
      income_source: source,
      cadence: "monthly",
      interval: 1,
      day_of_month: 1,
      weekday: nil,
      estimated_amount_cents: 500_000,
      start_on: Date.new(2026, 1, 1)
    )
    history_month = month.prev_month
    create(:transaction, account: checking, category: income, occurred_on: history_month, amount_cents: 400_000)
    windfall = create(:transaction, account: checking, category: windfalls, occurred_on: history_month + 1.day, amount_cents: 100_000)
    create(:transaction_classification, ledger_transaction: windfall, kind: "windfall")
    transfer_out = create(:transaction, account: checking, category: expense, occurred_on: history_month + 2.days, amount_cents: -200_000)
    transfer_in = create(:transaction, account: savings, category: income, occurred_on: history_month + 2.days, amount_cents: 200_000)
    create(:transaction_classification, ledger_transaction: transfer_out, paired_transaction: transfer_in, kind: "savings_transfer", group_key: "pair")
    create(:transaction_classification, ledger_transaction: transfer_in, paired_transaction: transfer_out, kind: "savings_transfer", group_key: "pair")
    create(:transaction, account: checking, category: expense, occurred_on: history_month + 3.days, amount_cents: -90_000)

    result = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: true)
    proposal = result.fetch(:proposal)

    assert_equal "draft", result[:status]
    assert_not result[:persisted]
    assert_equal 500_000, proposal[:recurring_outside_income_cents]
    assert_equal 500_000, proposal[:total_outside_income_previous_month_cents]
    assert_equal 166_666, proposal[:outside_income_averages_cents].fetch("3")
    assert_equal 133_333, proposal[:recurring_outside_income_averages_cents].fetch("3")
    assert_equal 30_000, proposal[:historical_category_spending_cents].fetch("3").fetch(expense.id.to_s)
    assert_equal TransactionClassification::TRANSFER_KINDS, proposal.dig(:exclusions, :transfer_kinds)
  end

  test "apply persists only an idempotent draft proposal" do
    month = Date.new(2026, 12, 1)

    first = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: false)
    second = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: false)

    assert_equal "draft", first[:status]
    assert_equal first[:proposal_id], second[:proposal_id]
    assert_equal 1, BudgetProposal.where(month: month).count
    assert_nil BudgetMonth.find_by(month: month)
  end
end
