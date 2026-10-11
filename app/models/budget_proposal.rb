class BudgetProposal < ApplicationRecord
  POLICY_VERSION = "budget-proposal-v1"
  STATUSES = %w[draft applied].freeze

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

  def total_assigned_cents
    proposed_expense_cents + proposed_savings_cents
  end

  def amount_remaining_cents
    proposed_income_cents - total_assigned_cents
  end

  private

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
  end

  def prevent_applied_proposal_deletion
    return unless applied?

    errors.add(:base, "Applied proposals cannot be deleted")
    throw :abort
  end
end
