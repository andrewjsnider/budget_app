class BudgetProposalsController < ApplicationController
  before_action :set_proposal, only: %i[show approve destroy]

  def index
    @proposals = BudgetProposal.includes(:budget_month).order(created_at: :desc)
    months = @proposals.map(&:month)
    @budget_months_by_month = BudgetMonth.where(month: months).index_by(&:month)
  end

  def show
    prepare_show
  end

  def approve
    result = BudgetProposals::Approve.call(@proposal, replace_existing: params[:replace_existing] == "1")

    if result.success?
      action = result.replaced? ? "replaced" : "created"
      redirect_to budget_month_path(month: result.budget_month.month.strftime("%Y-%m")),
        notice: "#{result.budget_month.month.strftime('%B %Y')} budget #{action}."
    else
      prepare_show
      @budget_month = result.existing_budget_month || @budget_month
      flash.now[:alert] = result.errors.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    if @proposal.applied?
      redirect_to budget_proposal_path(@proposal), alert: "Applied proposals cannot be deleted."
    elsif @proposal.destroy
      redirect_to budget_proposals_path, notice: "Proposal deleted."
    else
      redirect_to budget_proposal_path(@proposal), alert: @proposal.errors.full_messages.to_sentence
    end
  end

  private

  def set_proposal
    @proposal = BudgetProposal.find(params[:id])
  end

  def prepare_show
    @month = @proposal.month
    @validation = BudgetProposals::Validation.call(@proposal)
    @budget_month = @proposal.budget_month || BudgetMonth.find_by(month: @proposal.month)
    @ai_savings_recommendations = @proposal.savings_recommendations
    @additional_potential_monthly_cents = @proposal.estimated_additional_monthly_savings_cents
    @additional_potential_annual_cents = @proposal.estimated_additional_annual_savings_cents
    if @budget_month && !@proposal.applied?
      @budget_comparison = BudgetProposals::Comparison.call(@proposal, @budget_month)
    end
  end
end
