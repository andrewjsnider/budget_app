require "test_helper"

class FinancialPlanning::BudgetProposalBuilderTest < ActiveSupport::TestCase
  test "available income is the average of six explicit monthly paycheck totals" do
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
    monthly_paychecks = {
      month.prev_month(6) => [ 100_000, 200_000 ],
      month.prev_month(5) => [ 600_000 ],
      month.prev_month(4) => [ 700_000 ],
      month.prev_month(3) => [ 800_000 ],
      month.prev_month(2) => [ 900_000 ],
      month.prev_month => [ 1_000_000 ]
    }
    monthly_paychecks.each do |paycheck_month, amounts|
      amounts.each_with_index do |amount, index|
        create(:transaction, account: checking, category: income, occurred_on: paycheck_month + index.days, amount_cents: amount)
      end
    end
    history_month = month.prev_month
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
    assert_equal "ready", result[:review_status]
    assert_not result[:persisted]
    assert_equal "six_month_paycheck_average", proposal[:planning_baseline]
    assert_equal 716_667, proposal[:available_paycheck_income_cents]
    assert_equal 716_667, proposal[:paycheck_income_six_month_average_cents]
    assert_equal 6, proposal[:paycheck_income_monthly_totals_cents].length
    assert_equal 300_000, proposal[:paycheck_income_monthly_totals_cents].fetch(month.prev_month(6).iso8601)
    assert_equal 1_000_000, proposal[:paycheck_income_monthly_totals_cents].fetch(history_month.iso8601)
    refute_equal monthly_paychecks.values.flatten.sum / monthly_paychecks.values.flatten.length, proposal[:available_paycheck_income_cents]
    assert_equal 30_000, proposal[:historical_category_spending_cents].fetch("3").fetch(expense.id.to_s)
    assert proposal[:merchant_concentration].any? { |row| row.fetch(:category_name) == "Living" }
    assert_equal proposal[:proposed_savings_cents], proposal[:planned_savings_allocations].sum { |row| row.fetch(:proposed_cents) }
    assert_equal TransactionClassification::TRANSFER_KINDS, proposal.dig(:exclusions, :transfer_kinds)
  end

  test "legacy imported payroll rows use learned payroll descriptors without counting transfers or business income" do
    month = Date.new(2026, 11, 1)
    checking = create(:account, kind: "checking")
    paycheck = create(:category, name: "Paycheck", kind: "income")
    imported = create(:category, name: "Imported Income", kind: "income")
    business_income = create(:category, name: "Owner distribution", kind: "income")
    create(:income_source, account: checking, category: paycheck, kind: "W2")
    create(:income_source, account: checking, category: business_income, kind: "Business")
    create(:transaction, account: checking, category: imported, occurred_on: month.prev_month(6), description: "COLLEGE CENTRAL ACH PPD ID: 123", amount_cents: 100_000)
    create(:transaction, account: checking, category: imported, occurred_on: month.prev_month(6) + 1.day, description: "Online Transfer from SAV", amount_cents: 500_000)
    create(:transaction, account: checking, category: imported, occurred_on: month.prev_month(5), description: "COLLEGE CENTRAL PAYROLL PPD ID: 123", amount_cents: 200_000)
    create(:transaction, account: checking, category: paycheck, occurred_on: month.prev_month(4), amount_cents: 300_000)
    create(:transaction, account: checking, category: business_income, occurred_on: month.prev_month(3), amount_cents: 400_000)

    proposal = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: true).fetch(:proposal)
    totals = proposal.fetch(:paycheck_income_monthly_totals_cents)

    assert_equal 100_000, totals.fetch(month.prev_month(6).iso8601)
    assert_equal 200_000, totals.fetch(month.prev_month(5).iso8601)
    assert_equal 300_000, totals.fetch(month.prev_month(4).iso8601)
    assert_equal 0, totals.fetch(month.prev_month(3).iso8601)
    assert_equal 100_000, proposal.fetch(:available_paycheck_income_cents)
  end

  test "apply persists only an idempotent draft proposal" do
    month = Date.new(2026, 12, 1)

    first = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: false)
    second = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: false)

    assert_equal "draft", first[:status]
    assert_equal first[:proposal_id], second[:proposal_id]
    assert_equal 1, BudgetProposal.where(month: month).count
    persisted = BudgetProposal.find(first.fetch(:proposal_id))
    assert_empty persisted.savings_recommendations
    assert_nil BudgetMonth.find_by(month: month)
  end

  test "apply can supersede older drafts for the same month without applying a budget" do
    month = Date.new(2026, 12, 1)
    older = create(:budget_proposal, month:, proposal: {})

    result = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: false, supersede: true)

    assert_equal [ older.id ], result.fetch(:superseded_proposal_ids)
    refute BudgetProposal.exists?(older.id)
    assert BudgetProposal.exists?(result.fetch(:proposal_id))
    assert_nil BudgetMonth.find_by(month:)
  end


  test "stores recurring, subscription, trend, and merchant facts without fabricating recommendations" do
    month = Date.new(2026, 11, 1)
    account = create(:account)
    dining = create(:category, name: "Restaurants", kind: "expense")
    streaming = create(:category, name: "Streaming", kind: "expense")
    create(
      :recurring_expense,
      name: "Movie Stream",
      account: account,
      category: streaming,
      expense_type: "subscription",
      cadence: "monthly",
      interval: 1,
      day_of_month: 1,
      estimated_amount_cents: 1_500,
      start_on: Date.new(2026, 1, 1),
      active: true
    )
    create(:transaction, account:, category: dining, occurred_on: month.prev_month, description: "Local Cafe", amount_cents: -12_000)
    create(:transaction, account:, category: dining, occurred_on: month.prev_month(4), description: "Local Cafe", amount_cents: -6_000)

    result = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: false)
    proposal = BudgetProposal.find(result.fetch(:proposal_id))
    dining_row = proposal.proposed_categories.find { |row| row.fetch("category_id") == dining.id }
    streaming_row = proposal.proposed_categories.find { |row| row.fetch("category_id") == streaming.id }
    context = proposal.agent_financial_context

    assert_equal 1_500, context.fetch(:subscriptions).sole.fetch("projected_monthly_cents")
    assert_equal 1_500, streaming_row.fetch("proposed_cents")
    assert_equal "known_recurring_amount", streaming_row.fetch("calculation_basis")
    assert_equal 4_000, dining_row.dig("trend_data", "current_three_month_average_cents")
    assert_equal 2_000, dining_row.dig("trend_data", "prior_three_month_average_cents")
    assert_equal 3_000, dining_row.fetch("proposed_cents")
    assert_equal "six_month_spending_average", dining_row.fetch("calculation_basis")
    assert_equal "Local Cafe", context.fetch(:merchant_concentration).find { |row| row.fetch("category_id") == dining.id }.fetch("merchant")
    assert_empty proposal.savings_recommendations
  end


  test "a known recurring amount is not diluted by missing historical months" do
    month = Date.new(2026, 11, 1)
    account = create(:account)
    subscription = create(:category, name: "Cloud Storage", kind: "expense", group: "Subscriptions")
    recurring = create(
      :recurring_expense,
      name: "Cloud Storage",
      account:,
      category: subscription,
      expense_type: "subscription",
      estimated_amount_cents: 999,
      start_on: Date.new(2026, 1, 1)
    )
    create(:transaction, account:, category: subscription, occurred_on: month.prev_month, amount_cents: -999)

    proposal = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: true).fetch(:proposal)
    row = proposal.fetch(:proposed_categories).find { |candidate| candidate.fetch(:category_id) == subscription.id }

    assert_equal 167, row.dig(:average_spending_cents, "6")
    assert_equal 999, row.fetch(:proposed_cents)
    assert_equal "known_recurring_amount", row.fetch(:calculation_basis)
    assert_equal [ recurring.id ], row.fetch(:recurring_expense_ids)
  end


  test "a utility without a recurring record uses the same month last year plus fifteen percent" do
    month = Date.new(2026, 11, 1)
    account = create(:account)
    utility = create(:category, name: "Electricity & Gas", kind: "expense", group: "utilities")
    create(:transaction, account:, category: utility, occurred_on: month.prev_year + 3.days, amount_cents: -20_000)
    create(:transaction, account:, category: utility, occurred_on: month.prev_month, amount_cents: -60_000)

    proposal = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: true).fetch(:proposal)
    row = proposal.fetch(:proposed_categories).find { |candidate| candidate.fetch(:category_id) == utility.id }

    assert_equal 23_000, row.fetch(:proposed_cents)
    assert_equal "same_month_last_year_plus_15_percent", row.fetch(:calculation_basis)
  end


  test "a fixed utility with a recurring record uses its current amount instead of seasonal history" do
    month = Date.new(2026, 11, 1)
    account = create(:account)
    internet = create(:category, name: "Internet", kind: "expense", group: "utilities")
    create(
      :recurring_expense,
      name: "Internet",
      account:,
      category: internet,
      expense_type: "utility",
      estimated_amount_cents: 12_000,
      start_on: Date.new(2026, 1, 1)
    )
    create(:transaction, account:, category: internet, occurred_on: month.prev_year, amount_cents: -10_000)

    proposal = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: true).fetch(:proposal)
    row = proposal.fetch(:proposed_categories).find { |candidate| candidate.fetch(:category_id) == internet.id }

    assert_equal 12_000, row.fetch(:proposed_cents)
    assert_equal "known_recurring_amount", row.fetch(:calculation_basis)
  end


  test "a fixed-looking category without a recurring record is called out" do
    month = Date.new(2026, 11, 1)
    account = create(:account)
    subscription = create(:category, name: "Music", kind: "expense", group: "Subscriptions")
    create(:transaction, account:, category: subscription, occurred_on: month.prev_month, amount_cents: -1_200)

    proposal = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: true).fetch(:proposal)

    gap = proposal.fetch(:recurring_detection_gaps).sole
    assert_equal subscription.id, gap.fetch(:category_id)
    assert_includes gap.fetch(:warning), "no active RecurringExpense"
  end

  test "excludes non-budget categories from history and proposed categories" do
    month = Date.new(2026, 11, 1)
    account = create(:account, kind: "checking")
    income = create(:category, name: "Pay", kind: "income")
    normal = create(:category, name: "Groceries", kind: "expense")
    uncategorized = create(:category, name: "Uncategorized", kind: "expense")
    card_payments = create(:category, name: "Credit Card Payments", kind: "expense")
    history_month = month.prev_month

    create(:transaction, account:, category: normal, occurred_on: history_month, amount_cents: -10_000)
    create(:transaction, account:, category: uncategorized, occurred_on: history_month, amount_cents: -20_000)
    create(:transaction, account:, category: card_payments, occurred_on: history_month, amount_cents: -30_000)

    proposal = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: true).fetch(:proposal)
    proposed_names = proposal.fetch(:proposed_categories).map { |row| row.fetch(:category_name) }
    history = proposal.fetch(:historical_category_spending_cents).fetch("3")

    assert_includes proposed_names, "Groceries"
    refute_includes proposed_names, "Uncategorized"
    refute_includes proposed_names, "Credit Card Payments"
    assert_equal 3_333, history.fetch(normal.id.to_s)
    refute history.key?(uncategorized.id.to_s)
    refute history.key?(card_payments.id.to_s)
    assert_equal 20_000, proposal.fetch(:excluded_category_spending_cents).fetch("Uncategorized")
    assert_equal 30_000, proposal.fetch(:excluded_category_spending_cents).fetch("Credit Card Payments")
  end
end
