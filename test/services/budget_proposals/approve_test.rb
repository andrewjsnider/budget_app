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
    assert_equal proposal.proposed_savings_cents, proposal.budget_month.planned_savings_cents
    assert_equal proposal.planned_savings_allocations, proposal.budget_month.planned_savings_allocations
    refute proposal.replaced_existing_budget?
    assert_nil proposal.replaced_at
  end

  test "an existing budget requires explicit replacement authorization" do
    category = create(:category)
    proposal = create(:budget_proposal, proposal: proposal_payload(category => 50_000))
    existing = BudgetMonth.create!(month: proposal.month)
    existing.budget_items.create!(category:, assigned_cents: 12_300)

    assert_no_difference([ "BudgetMonth.count", "BudgetItem.count" ]) do
      result = BudgetProposals::Approve.call(proposal)
      refute result.success?
      assert_equal existing, result.existing_budget_month
      assert_includes result.errors.join, "Confirm that you want to replace"
    end

    assert_equal 12_300, existing.budget_items.sole.assigned_cents
    assert_equal "draft", proposal.reload.status
  end

  test "replacement preserves the budget month and replaces only its plan" do
    retained = create(:category, name: "Retained")
    removed = create(:category, name: "Removed")
    account = create(:account)
    proposal = create(:budget_proposal, proposal: proposal_payload(retained => 50_000))
    existing = BudgetMonth.create!(
      month: proposal.month,
      planned_savings_cents: 5_000,
      planned_savings_allocations: [ { "name" => "Old savings", "proposed_cents" => 5_000 } ]
    )
    existing.budget_items.create!(category: retained, assigned_cents: 12_300)
    existing.budget_items.create!(category: removed, assigned_cents: 8_000)
    transaction = create(
      :transaction,
      account:,
      category: removed,
      occurred_on: proposal.month + 2.days,
      amount_cents: -2_500
    )

    assert_no_difference([ "BudgetMonth.count", "Transaction.count" ]) do
      result = BudgetProposals::Approve.call(proposal, replace_existing: true)
      assert result.success?
      assert result.replaced?
      assert_equal existing.id, result.budget_month.id
    end

    assert_equal({ retained.id => 50_000 }, existing.reload.budget_items.pluck(:category_id, :assigned_cents).to_h)
    assert_equal proposal.proposed_savings_cents, existing.planned_savings_cents
    assert_equal proposal.planned_savings_allocations, existing.planned_savings_allocations
    assert_equal removed, transaction.reload.category
    assert_equal(-2_500, transaction.amount_cents)

    proposal.reload
    assert proposal.applied?
    assert proposal.replaced_existing_budget?
    assert proposal.replaced_at.present?
    assert_equal existing, proposal.budget_month
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

  test "a partial replacement failure restores the old assignments and savings" do
    old_category = create(:category, name: "Old")
    first = create(:category, name: "First")
    second = create(:category, name: "Second")
    proposal = create(:budget_proposal, proposal: proposal_payload(first => 10_000, second => 20_000))
    existing = BudgetMonth.create!(
      month: proposal.month,
      planned_savings_cents: 7_000,
      planned_savings_allocations: [ { "name" => "Old savings", "proposed_cents" => 7_000 } ]
    )
    existing.budget_items.create!(category: old_category, assigned_cents: 33_000)
    failing_service = Class.new(BudgetProposals::Approve) do
      private

      def create_assignment!(budget_month, row)
        super
        raise ActiveRecord::RecordInvalid, BudgetItem.new if row.fetch("proposed_cents") == 20_000
      end
    end

    result = failing_service.new(proposal, replace_existing: true).call

    refute result.success?
    assert_equal({ old_category.id => 33_000 }, existing.reload.budget_items.pluck(:category_id, :assigned_cents).to_h)
    assert_equal 7_000, existing.planned_savings_cents
    assert_equal [ { "name" => "Old savings", "proposed_cents" => 7_000 } ], existing.planned_savings_allocations
    assert_equal "draft", proposal.reload.status
    assert_nil proposal.budget_month_id
    refute proposal.replaced_existing_budget?
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

  test "an applied replacement cannot replace the budget twice" do
    category = create(:category)
    proposal = create(:budget_proposal, proposal: proposal_payload(category => 50_000))
    existing = BudgetMonth.create!(month: proposal.month)
    first = BudgetProposals::Approve.call(proposal, replace_existing: true)

    assert_no_difference([ "BudgetMonth.count", "BudgetItem.count" ]) do
      second = BudgetProposals::Approve.call(proposal.reload, replace_existing: true)
      refute second.success?
      assert_equal first.budget_month, second.existing_budget_month
      assert_includes second.errors, "This proposal has already been applied."
    end

    assert_equal existing.id, proposal.reload.budget_month_id
  end

  test "a later proposal can replace a budget while preserving the earlier proposal audit" do
    category = create(:category)
    first_proposal = create(:budget_proposal, proposal: proposal_payload(category => 40_000))
    budget = BudgetProposals::Approve.call(first_proposal).budget_month
    second_proposal = create(
      :budget_proposal,
      month: first_proposal.month,
      proposal: proposal_payload(category => 55_000)
    )

    result = BudgetProposals::Approve.call(second_proposal, replace_existing: true)

    assert result.success?
    assert result.replaced?
    assert_equal budget.id, result.budget_month.id
    assert_equal budget.id, first_proposal.reload.budget_month_id
    assert_equal budget.id, second_proposal.reload.budget_month_id
    assert first_proposal.applied?
    assert second_proposal.applied?
    assert second_proposal.replaced_existing_budget?
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
      "planned_savings_allocations" => [
        { "name" => "Planned savings", "proposed_cents" => 100_000 - expenses }
      ],
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
