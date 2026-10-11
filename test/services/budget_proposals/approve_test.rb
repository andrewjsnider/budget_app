require "test_helper"

class BudgetProposals::ApproveTest < ActiveSupport::TestCase
  test "approving a valid proposal atomically creates the budget and every assignment" do
    groceries = create(:category, name: "Groceries")
    utilities = create(:category, name: "Utilities")
    proposal = create(:budget_proposal, proposal: proposal_payload(groceries => 40_000, utilities => 20_000))

    assert_difference("BudgetMonth.count", 1) do
      assert_difference("BudgetItem.count", 2) do
        result = BudgetProposals::Approve.call(proposal)
        assert result.success?
      end
    end

    proposal.reload
    assert_equal "applied", proposal.status
    assert proposal.applied_at.present?
    assert_equal proposal.month, proposal.budget_month.month
    assert_equal({ groceries.id => 40_000, utilities.id => 20_000 }, proposal.budget_month.budget_items.pluck(:category_id, :assigned_cents).to_h)
  end

  test "an existing budget month is never overwritten" do
    category = create(:category)
    proposal = create(:budget_proposal, proposal: proposal_payload(category => 50_000))
    existing = BudgetMonth.create!(month: proposal.month)
    existing.budget_items.create!(category:, assigned_cents: 12_300)

    assert_no_difference([ "BudgetMonth.count", "BudgetItem.count" ]) do
      result = BudgetProposals::Approve.call(proposal)
      refute result.success?
      assert_equal existing, result.existing_budget_month
      assert_includes result.errors.join, "already exists"
    end

    assert_equal 12_300, existing.budget_items.sole.assigned_cents
    assert_equal "draft", proposal.reload.status
  end

  test "an invalid proposal cannot be approved" do
    category = create(:category)
    payload = proposal_payload(category => 50_000).merge("proposed_expense_total_cents" => 49_999)
    proposal = create(:budget_proposal, proposal: payload)

    assert_no_difference([ "BudgetMonth.count", "BudgetItem.count" ]) do
      result = BudgetProposals::Approve.call(proposal)
      refute result.success?
      assert_includes result.errors, "Category assignments do not equal the proposed expense total."
    end

    assert_equal "draft", proposal.reload.status
  end

  test "a partial assignment failure rolls back the budget and proposal update" do
    first = create(:category, name: "First")
    second = create(:category, name: "Second")
    proposal = create(:budget_proposal, proposal: proposal_payload(first => 10_000, second => 20_000))
    failing_service = Class.new(BudgetProposals::Approve) do
      private

      def create_assignment!(budget_month, row)
        super
        raise ActiveRecord::RecordInvalid, BudgetItem.new if row.fetch("proposed_cents") == 20_000
      end
    end

    assert_no_difference([ "BudgetMonth.count", "BudgetItem.count" ]) do
      result = failing_service.new(proposal).call
      refute result.success?
    end

    assert_equal "draft", proposal.reload.status
    assert_nil proposal.budget_month_id
  end

  test "an applied proposal cannot be approved twice" do
    category = create(:category)
    proposal = create(:budget_proposal, proposal: proposal_payload(category => 50_000))
    first = BudgetProposals::Approve.call(proposal)

    assert_no_difference([ "BudgetMonth.count", "BudgetItem.count" ]) do
      second = BudgetProposals::Approve.call(proposal.reload)
      refute second.success?
      assert_equal first.budget_month, second.existing_budget_month
      assert_includes second.errors, "This proposal has already been applied."
    end
  end

  private

  def proposal_payload(assignments)
    month = Date.current.next_month.beginning_of_month
    expenses = assignments.values.sum

    {
      "month" => month.iso8601,
      "planning_baseline" => "recurring_outside_income",
      "recurring_outside_income_cents" => 100_000,
      "proposed_expense_total_cents" => expenses,
      "proposed_savings_cents" => 100_000 - expenses,
      "proposed_categories" => assignments.map do |category, amount|
        {
          "category_id" => category.id,
          "category_name" => category.name,
          "proposed_cents" => amount,
          "average_spending_cents" => { "3" => amount, "6" => amount, "12" => amount },
          "rationale" => "max(previous_budget, three_month_average, recurring_obligation)"
        }
      end
    }
  end
end
