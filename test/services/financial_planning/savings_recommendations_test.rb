require "test_helper"

class FinancialPlanning::SavingsRecommendationsTest < ActiveSupport::TestCase
  test "recommends a saved spending baseline without changing proposal totals" do
    payload = {
      "recurring_outside_income_cents" => 100_000,
      "proposed_expense_total_cents" => 60_000,
      "proposed_savings_cents" => 40_000,
      "proposed_categories" => [
        {
          "category_id" => 1,
          "category_name" => "Dining Out",
          "proposed_cents" => 40_000,
          "recurring_obligation_cents" => 0,
          "average_spending_cents" => { "3" => 40_000, "6" => 25_000 }
        },
        {
          "category_id" => 2,
          "category_name" => "Utilities",
          "proposed_cents" => 20_000,
          "recurring_obligation_cents" => 20_000,
          "average_spending_cents" => { "3" => 20_000, "6" => 15_000 }
        }
      ]
    }
    proposal = build(:budget_proposal, proposal: payload.deep_dup)

    recommendation = FinancialPlanning::SavingsRecommendations.call(proposal).sole

    assert_equal "Dining Out", recommendation.category_name
    assert_equal "3-month average", recommendation.current_spending_basis
    assert_equal 40_000, recommendation.current_spending_cents
    assert_equal 25_000, recommendation.suggested_target_cents
    assert_equal 15_000, recommendation.potential_monthly_savings_cents
    assert_equal 180_000, recommendation.potential_annual_savings_cents
    assert_equal 60_000, proposal.proposed_expense_cents
    assert_equal 40_000, proposal.proposed_savings_cents
    assert_equal 100_000, proposal.total_assigned_cents
    assert_equal payload, proposal.proposal
  end
end
