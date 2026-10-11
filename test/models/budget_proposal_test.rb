require "test_helper"

class BudgetProposalTest < ActiveSupport::TestCase
  test "planned savings, savings rate, allocation total, and unassigned amount stay distinct" do
    proposal = build(:budget_proposal, proposal: {
      "recurring_outside_income_cents" => 620_000,
      "proposed_expense_total_cents" => 530_000,
      "proposed_savings_cents" => 90_000,
      "planned_savings_allocations" => [
        { "name" => "Emergency Fund", "proposed_cents" => 40_000 },
        { "name" => "General Savings", "proposed_cents" => 30_000 },
        { "name" => "Vacation", "proposed_cents" => 20_000 }
      ]
    })

    assert_equal 90_000, proposal.proposed_savings_cents
    assert_equal 90_000, proposal.planned_savings_allocations_total_cents
    assert_in_delta 14.516, proposal.savings_rate_percentage, 0.001
    assert_equal 0, proposal.amount_remaining_cents
  end

  test "a proposal with no paycheck income has a zero savings rate" do
    proposal = build(:budget_proposal, proposal: {
      "recurring_outside_income_cents" => 0,
      "proposed_expense_total_cents" => 0,
      "proposed_savings_cents" => 0
    })

    assert_equal 0.0, proposal.savings_rate_percentage
    assert_equal 0, proposal.amount_remaining_cents
  end

  test "savings category assignments are used as a breakdown when they reconcile to planned savings" do
    emergency = create(:category, name: "Emergency Fund", group: "Savings")
    vacation = create(:category, name: "Vacation", group: "Savings")
    proposal = build(:budget_proposal, proposal: {
      "proposed_savings_cents" => 90_000,
      "proposed_categories" => [
        { "category_id" => emergency.id, "category_name" => emergency.name, "proposed_cents" => 40_000 },
        { "category_id" => vacation.id, "category_name" => vacation.name, "proposed_cents" => 50_000 }
      ]
    })

    assert_equal [ "Emergency Fund", "Vacation" ], proposal.planned_savings_allocations.pluck("name")
    assert_equal 90_000, proposal.planned_savings_allocations_total_cents
  end
end
