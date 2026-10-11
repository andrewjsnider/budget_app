require "test_helper"

class BudgetProposals::ValidationTest < ActiveSupport::TestCase
  test "ready validation requires six explicit paycheck totals and their arithmetic mean" do
    month = Date.new(2026, 11, 1)
    account = create(:account)
    income = create(:category, kind: "income")
    create(:income_source, account:, category: income)
    6.downto(1) do |offset|
      create(:transaction, account:, category: income, occurred_on: month.prev_month(offset), amount_cents: offset * 10_000)
    end
    proposal = build_proposal(month)

    assert BudgetProposals::Validation.call(proposal).valid?

    payload = proposal.proposal.deep_dup
    payload["available_paycheck_income_cents"] += 1
    proposal.update!(proposal: payload)

    validation = BudgetProposals::Validation.call(proposal)
    refute validation.valid?
    assert_includes validation.errors, "Available income does not equal the six-month paycheck average."
  end

  test "ready validation rejects dilution or double counting of a current recurring amount" do
    month = Date.new(2026, 11, 1)
    account = create(:account)
    income = create(:category, kind: "income")
    category = create(:category, name: "Cloud Storage", group: "Subscriptions")
    create(:income_source, account:, category: income)
    6.downto(1) do |offset|
      create(:transaction, account:, category: income, occurred_on: month.prev_month(offset), amount_cents: 10_000)
    end
    create(
      :recurring_expense,
      account:,
      category:,
      expense_type: "subscription",
      estimated_amount_cents: 999,
      start_on: Date.new(2026, 1, 1)
    )
    create(:transaction, account:, category:, occurred_on: month.prev_month, amount_cents: -999)
    proposal = build_proposal(month)

    assert BudgetProposals::Validation.call(proposal).valid?

    payload = proposal.proposal.deep_dup
    row = payload.fetch("proposed_categories").sole
    row["proposed_cents"] = row.dig("average_spending_cents", "6")
    row["calculation_basis"] = "six_month_spending_average"
    payload["proposed_expense_total_cents"] = row.fetch("proposed_cents")
    proposal.update!(proposal: payload)

    validation = BudgetProposals::Validation.call(proposal)
    refute validation.valid?
    assert validation.errors.any? { |error| error.include?("known current recurring amount") }
  end

  private

  def build_proposal(month)
    result = FinancialPlanning::BudgetProposalBuilder.call(month:, dry_run: false)
    BudgetProposal.find(result.fetch(:proposal_id))
  end
end
