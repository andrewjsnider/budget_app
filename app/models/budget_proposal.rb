class BudgetProposal < ApplicationRecord
  POLICY_VERSION = "budget-proposal-v1"
  STATUSES = %w[draft applied].freeze
  SAVINGS_CATEGORY_PATTERN = /\b(savings|emergency fund|vacation fund)\b/i

  belongs_to :budget_month, optional: true

  validates :month, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :policy_version, :input_digest, :source, presence: true
  validates :input_digest, uniqueness: { scope: :month }, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :month_starts_on_first_day
  validate :application_fields_match_status

  before_destroy :prevent_applied_proposal_deletion

  def applied?
    status == "applied"
  end

  def proposed_categories
    rows = proposal["proposed_categories"]
    rows.is_a?(Array) ? rows.select { |row| row.is_a?(Hash) } : []
  end

  def proposed_income_cents
    proposal.fetch("recurring_outside_income_cents", 0).to_i
  end

  def proposed_expense_cents
    proposal.fetch("proposed_expense_total_cents", 0).to_i
  end

  def proposed_savings_cents
    proposal.fetch("proposed_savings_cents", 0).to_i
  end

  def savings_rate_percentage
    return 0.0 unless proposed_income_cents.positive?

    proposed_savings_cents.fdiv(proposed_income_cents) * 100
  end

  def planned_savings_allocations
    rows = proposal["planned_savings_allocations"]
    return rows.select { |row| row.is_a?(Hash) } if rows.is_a?(Array)

    inferred = inferred_savings_allocations
    inferred.sum { |allocation| allocation.fetch("proposed_cents") } == proposed_savings_cents ? inferred : default_savings_allocation
  end

  def planned_savings_allocations_total_cents
    planned_savings_allocations.sum { |allocation| allocation.fetch("proposed_cents", 0).to_i }
  end

  def savings_category_assignment?(row)
    group = row["category_group"]
    name = row["category_name"]
    if group.blank? && row["category_id"].present?
      group, stored_name = Category.where(id: row["category_id"]).pick(:group, :name)
      name ||= stored_name
    end

    group.to_s.casecmp("savings").zero? || name.to_s.match?(SAVINGS_CATEGORY_PATTERN)
  end

  def total_assigned_cents
    proposed_expense_cents + proposed_savings_cents
  end

  def amount_remaining_cents
    proposed_income_cents - total_assigned_cents
  end

  def savings_recommendations
    rows = ai_savings_recommendations
    rows.is_a?(Array) ? rows.select { |row| row.is_a?(Hash) } : []
  end

  def estimated_additional_monthly_savings_cents
    savings_recommendations.sum { |row| row.fetch("estimated_monthly_savings_cents", 0).to_i }
  end

  def estimated_additional_annual_savings_cents
    savings_recommendations.sum { |row| row.fetch("estimated_annual_savings_cents", 0).to_i }
  end

  def agent_financial_context
    validation = BudgetProposals::Validation.call(self)

    {
      proposal_id: id,
      month: month.iso8601,
      status: status,
      review_status: applied? ? "applied" : (validation.valid? ? "ready" : "invalid"),
      policy_version: policy_version,
      income: {
        planning_baseline: proposal["planning_baseline"],
        available_paycheck_income_cents: proposed_income_cents,
        monthly_paycheck_totals_cents: proposal.fetch("recurring_outside_income_monthly_totals_cents", {}),
        paycheck_averages_cents: proposal.fetch("recurring_outside_income_averages_cents", {}),
        total_income_previous_month_cents: proposal["total_outside_income_previous_month_cents"]
      },
      proposed_income_cents: proposed_income_cents,
      proposed_expense_cents: proposed_expense_cents,
      proposed_savings_cents: proposed_savings_cents,
      planned_savings_allocations: planned_savings_allocations,
      savings_rate_percentage: savings_rate_percentage.round(2),
      amount_remaining_cents: amount_remaining_cents,
      proposed_categories: proposed_categories,
      recurring_obligations: proposal.fetch("recurring_obligation_details", []),
      subscriptions: proposal.fetch("subscriptions", []),
      merchant_concentration: proposal.fetch("merchant_concentration", []),
      excluded_category_spending_cents: proposal.fetch("excluded_category_spending_cents", {}),
      unresolved_transactions: proposal.fetch("unresolved_transactions", {}),
      validation_errors: validation.errors,
      validation_warnings: validation.warnings
    }
  end

  private

  def default_savings_allocation
    return [] unless proposed_savings_cents.positive?

    [ { "name" => "Planned savings", "proposed_cents" => proposed_savings_cents } ]
  end

  def inferred_savings_allocations
    proposed_categories.filter_map do |row|
      next unless savings_category_assignment?(row)

      {
        "name" => row.fetch("category_name", "Savings"),
        "proposed_cents" => row.fetch("proposed_cents", 0).to_i
      }
    end
  end

  def month_starts_on_first_day
    errors.add(:month, "must be the first day of the month") if month.present? && month.day != 1
  end

  def application_fields_match_status
    if applied?
      errors.add(:budget_month, "must be linked when applied") if budget_month_id.blank?
      errors.add(:applied_at, "must be present when applied") if applied_at.blank?
    elsif budget_month_id.present? || applied_at.present?
      errors.add(:base, "A draft proposal cannot be linked to a budget")
    end

    if replaced_existing_budget?
      errors.add(:replaced_at, "must be present when an existing budget was replaced") if replaced_at.blank?
      errors.add(:base, "Only an applied proposal can record a replacement") unless applied?
    elsif replaced_at.present?
      errors.add(:replaced_at, "must be blank when no budget was replaced")
    end
  end

  def prevent_applied_proposal_deletion
    return unless applied?

    errors.add(:base, "Applied proposals cannot be deleted")
    throw :abort
  end
end
