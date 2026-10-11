require "test_helper"

class FinancialActions::StoreBudgetProposalSavingsRecommendationsTest < ActiveSupport::TestCase
  test "preview validates without writing and apply stores an auditable recommendation snapshot" do
    proposal = create(:budget_proposal, proposal: proposal_totals)
    input = recommendation_input(proposal)

    preview = nil
    assert_no_changes -> { proposal.reload.ai_savings_recommendations } do
      preview = FinancialActions::StoreBudgetProposalSavingsRecommendations.call(input:, dry_run: true)
    end

    result = FinancialActions::StoreBudgetProposalSavingsRecommendations.call(input:, dry_run: false)
    stored = proposal.reload.savings_recommendations.sole

    assert_equal 1, preview.fetch(:recommendation_count)
    assert_equal 1, result.fetch(:recommendation_count)
    assert_equal "Review restaurant frequency", stored.fetch("title")
    assert_equal "Restaurants", stored.fetch("category_or_merchant")
    assert_equal "medium", stored.fetch("confidence")
    assert_equal [ "Six-month average is $420", "Three merchants account for 72% of spending" ], stored.fetch("supporting_evidence")
    assert_equal FinancialActions::StoreBudgetProposalSavingsRecommendations::POLICY_VERSION, stored.fetch("policy_version")
    assert_equal "draft", proposal.status
  end

  test "recommendations do not change proposal totals or assignments" do
    proposal = create(:budget_proposal, proposal: proposal_totals.deep_dup)
    original_payload = proposal.proposal.deep_dup

    FinancialActions::StoreBudgetProposalSavingsRecommendations.call(
      input: recommendation_input(proposal),
      dry_run: false
    )

    proposal.reload
    assert_equal original_payload, proposal.proposal
    assert_equal 60_000, proposal.proposed_expense_cents
    assert_equal 40_000, proposal.proposed_savings_cents
    assert_equal 100_000, proposal.total_assigned_cents
    assert_equal 10_000, proposal.estimated_additional_monthly_savings_cents
  end

  test "invalid or unsupported recommendation data is rejected" do
    proposal = create(:budget_proposal, proposal: proposal_totals)
    input = recommendation_input(proposal)
    input.fetch("recommendations").first["supporting_evidence"] = []

    assert_raises(FinancialActions::InputFile::InvalidInput) do
      FinancialActions::StoreBudgetProposalSavingsRecommendations.call(input:, dry_run: false)
    end

    assert_empty proposal.reload.savings_recommendations
  end

  private

  def proposal_totals
    {
      "recurring_outside_income_cents" => 100_000,
      "proposed_expense_total_cents" => 60_000,
      "proposed_savings_cents" => 40_000
    }
  end

  def recommendation_input(proposal)
    {
      "proposal_id" => proposal.id,
      "recommendations" => [
        {
          "title" => "Review restaurant frequency",
          "category_or_merchant" => "Restaurants",
          "explanation" => "Repeated discretionary purchases are concentrated at three merchants.",
          "current_spending_cents" => 42_000,
          "suggested_target_cents" => 32_000,
          "estimated_monthly_savings_cents" => 10_000,
          "estimated_annual_savings_cents" => 120_000,
          "confidence" => "medium",
          "supporting_evidence" => [
            "Six-month average is $420",
            "Three merchants account for 72% of spending"
          ]
        }
      ]
    }
  end
end
