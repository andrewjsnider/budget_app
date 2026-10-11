require "test_helper"

class BudgetProposalsTest < ActionDispatch::IntegrationTest
  def setup
    @user = create(:user)
    @category = create(:category, name: "Groceries")
    sign_in @user
  end

  test "index lists newest proposals, totals, status, and existing budget state" do
    older = create(:budget_proposal, created_at: 2.days.ago, proposal: proposal_payload)
    newer = create(:budget_proposal, month: older.month.next_month, created_at: 1.day.ago, proposal: proposal_payload(month: older.month.next_month))
    BudgetMonth.create!(month: older.month)

    get budget_proposals_path

    assert_response :success
    assert_select "tbody tr", count: 2
    assert_operator response.body.index(newer.month.strftime("%B %Y")), :<, response.body.index(older.month.strftime("%B %Y"))
    assert_includes response.body, "$1,000.00"
    assert_includes response.body, "$400.00"
    assert_includes response.body, "$500.00"
    assert_includes response.body, "$900.00"
    assert_includes response.body, "Ready"
    assert_select "a", text: "Yes — View"
    assert_select "a", text: "View", count: 2
  end

  test "show displays the review details and approval action" do
    proposal = create(:budget_proposal, proposal: proposal_payload)

    get budget_proposal_path(proposal)

    assert_response :success
    assert_includes response.body, proposal.month.strftime("%B %Y")
    assert_select "h2", text: "Income"
    assert_select "h2", text: "Proposed Budget"
    assert_select "h2", text: "Savings"
    assert_select "h3", text: "Ways to save more"
    assert_includes response.body, "Six-month paycheck average"
    assert_includes response.body, "$1,000.00"
    assert_includes response.body, "$400.00"
    assert_includes response.body, "$500.00"
    assert_includes response.body, "$900.00"
    assert_includes response.body, "$100.00"
    assert_select "#planned-savings-summary", text: /\$500\.00/
    assert_select "#savings-rate-summary", text: /50\.0%/
    assert_select "#additional-savings-summary", text: /\$50\.00/
    assert_select "#savings", text: /Emergency Fund.*\$300\.00/m
    assert_select "#savings", text: /Vacation.*\$200\.00/m
    assert_select "#savings", text: /Total planned savings.*\$500\.00/m
    assert_select "#savings", text: /\$50\.00 \/ month/
    assert_select "#savings", text: /\$600\.00 \/ year/
    assert_includes response.body, "Groceries"
    assert_includes response.body, "3-month spending average"
    assert_includes response.body, "Excluded Uncategorized spending"
    assert_select "form[action='#{approve_budget_proposal_path(proposal)}'] button", text: "Approve and Create Budget"
    assert_select "form[action='#{budget_proposal_path(proposal)}'] button", text: "Delete Proposal"
  end

  test "zero-based proposal displays no unassigned amount" do
    payload = proposal_payload.merge(
      "proposed_savings_cents" => 60_000,
      "planned_savings_allocations" => [ { "name" => "General Savings", "proposed_cents" => 60_000 } ]
    )
    proposal = create(:budget_proposal, proposal: payload)

    get budget_proposal_path(proposal)

    assert_response :success
    assert_select "#unassigned-amount", text: /Unassigned.*\$0\.00/m
    assert_select "#planned-savings-summary", text: /\$600\.00/
    assert_select "#savings-rate-summary", text: /60\.0%/
  end

  test "approving redirects to the actual budget and shows the success copy" do
    proposal = create(:budget_proposal, proposal: proposal_payload)

    post approve_budget_proposal_path(proposal)

    budget = proposal.reload.budget_month
    assert_redirected_to budget_month_path(month: budget.month.strftime("%Y-%m"))
    follow_redirect!
    assert_response :success
    assert_includes response.body, "#{budget.month.strftime('%B %Y')} budget created."
    assert_equal 40_000, budget.budget_items.find_by!(category: @category).assigned_cents
  end

  test "an unconfirmed request cannot replace an existing budget" do
    proposal = create(:budget_proposal, proposal: proposal_payload)
    existing = BudgetMonth.create!(month: proposal.month)

    post approve_budget_proposal_path(proposal)

    assert_response :unprocessable_entity
    assert_includes response.body, "Confirm that you want to replace"
    assert_select "a[href='#{budget_month_path(month: existing.month.strftime('%Y-%m'))}']", text: "View Existing Budget"
    assert_equal "draft", proposal.reload.status
  end

  test "existing budget shows comparison and can be explicitly replaced" do
    removed = create(:category, name: "Old Category")
    income = create(:category, name: "Paycheck", kind: "income")
    account = create(:account)
    proposal = create(:budget_proposal, proposal: proposal_payload)
    existing = BudgetMonth.create!(
      month: proposal.month,
      planned_savings_cents: 10_000,
      planned_savings_allocations: [ { "name" => "Old savings", "proposed_cents" => 10_000 } ]
    )
    existing.budget_items.create!(category: @category, assigned_cents: 12_300)
    existing.budget_items.create!(category: removed, assigned_cents: 8_000)
    create(:transaction, account:, category: income, occurred_on: proposal.month, amount_cents: 100_000)

    get budget_proposal_path(proposal)

    assert_response :success
    assert_includes response.body, "#{proposal.month.strftime('%B %Y')} already has a budget."
    assert_includes response.body, "Historical transactions and account data will not change."
    assert_select "a[href='#{budget_month_path(month: existing.month.strftime('%Y-%m'))}']", text: "View Existing Budget"
    assert_select "form[action='#{approve_budget_proposal_path(proposal)}'] button", text: "Replace Existing Budget"
    assert_select "form[action='#{approve_budget_proposal_path(proposal)}'] input[name='replace_existing'][value='1']"
    assert_select "form[data-turbo-confirm*='Historical transactions will not be changed.']"
    assert_select "form[action='#{approve_budget_proposal_path(proposal)}'] button", text: "Approve and Create Budget", count: 0
    assert_select "#budget-comparison", text: /Total income.*\$1,000\.00.*\$1,000\.00/m
    assert_select "#budget-comparison", text: /Total spending.*\$203\.00.*\$400\.00/m
    assert_select "#budget-comparison", text: /Planned savings.*\$100\.00.*\$500\.00/m
    assert_select "#budget-comparison", text: /Savings rate.*10\.0%.*50\.0%/m
    assert_select "#budget-comparison", text: /Old Category.*\$80\.00.*\$0\.00/m

    post approve_budget_proposal_path(proposal), params: { replace_existing: "1" }

    assert_redirected_to budget_month_path(month: proposal.month.strftime("%Y-%m"))
    follow_redirect!
    assert_includes response.body, "#{proposal.month.strftime('%B %Y')} budget replaced."
    assert_equal existing.id, proposal.reload.budget_month_id
    assert_equal({ @category.id => 40_000 }, existing.reload.budget_items.pluck(:category_id, :assigned_cents).to_h)
  end

  test "invalid proposal is visibly invalid and cannot be applied" do
    payload = proposal_payload.merge("proposed_expense_total_cents" => 1)
    proposal = create(:budget_proposal, proposal: payload)

    get budget_proposal_path(proposal)
    assert_response :success
    assert_includes response.body, "Invalid"
    assert_select "form[action='#{approve_budget_proposal_path(proposal)}']", count: 0

    post approve_budget_proposal_path(proposal)
    assert_response :unprocessable_entity
    assert_nil BudgetMonth.find_by(month: proposal.month)
    assert_equal "draft", proposal.reload.status
  end

  test "a draft can be deleted without affecting budgets" do
    proposal = create(:budget_proposal, proposal: proposal_payload)
    unrelated_budget = BudgetMonth.create!(month: proposal.month.prev_month)

    assert_difference("BudgetProposal.count", -1) do
      assert_no_difference("BudgetMonth.count") do
        delete budget_proposal_path(proposal)
      end
    end

    assert_redirected_to budget_proposals_path
    assert BudgetMonth.exists?(unrelated_budget.id)
  end

  test "an applied proposal links to its budget and cannot be deleted" do
    proposal = create(:budget_proposal, proposal: proposal_payload)
    budget = BudgetProposals::Approve.call(proposal).budget_month

    get budget_proposal_path(proposal.reload)
    assert_response :success
    assert_includes response.body, "Applied"
    assert_select "a[href='#{budget_month_path(month: budget.month.strftime('%Y-%m'))}']", text: "View Budget"
    assert_select "form[action='#{approve_budget_proposal_path(proposal)}']", count: 0

    assert_no_difference([ "BudgetProposal.count", "BudgetMonth.count", "BudgetItem.count" ]) do
      delete budget_proposal_path(proposal)
    end
    assert_redirected_to budget_proposal_path(proposal)
    assert BudgetMonth.exists?(budget.id)
  end

  test "the normal budget page links to proposals" do
    get budget_month_path(month: Date.current.strftime("%Y-%m"))

    assert_response :success
    assert_select "a[href='#{budget_proposals_path}']", text: "Budget Proposals"
  end

  private

  def proposal_payload(month: Date.current.next_month.beginning_of_month)
    {
      "month" => month.iso8601,
      "planning_baseline" => "recurring_outside_income",
      "recurring_outside_income_cents" => 100_000,
      "recurring_outside_income_monthly_totals_cents" => 6.downto(1).to_h { |offset| [ month.prev_month(offset).iso8601, 100_000 ] },
      "recurring_outside_income_averages_cents" => { "6" => 100_000 },
      "proposed_expense_total_cents" => 40_000,
      "proposed_savings_cents" => 50_000,
      "planned_savings_allocations" => [
        { "name" => "Emergency Fund", "proposed_cents" => 30_000 },
        { "name" => "Vacation", "proposed_cents" => 20_000 }
      ],
      "excluded_category_spending_cents" => { "Uncategorized" => 12_000, "Credit Card Payments" => 0 },
      "proposed_categories" => [
        {
          "category_id" => @category.id,
          "category_name" => @category.name,
          "proposed_cents" => 40_000,
          "average_spending_cents" => { "3" => 40_000, "6" => 35_000, "12" => 30_000 },
          "recurring_obligation_cents" => 0,
          "previous_budget_cents" => 0,
          "rationale" => "max(previous_budget, three_month_average, recurring_obligation)"
        }
      ]
    }
  end
end
