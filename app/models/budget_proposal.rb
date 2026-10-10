class BudgetProposal < ApplicationRecord
  POLICY_VERSION = "budget-proposal-v1"

  validates :month, presence: true
  validates :status, inclusion: { in: %w[draft] }
  validates :policy_version, :input_digest, :source, presence: true
  validates :input_digest, uniqueness: { scope: :month }, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :month_starts_on_first_day

  private

  def month_starts_on_first_day
    errors.add(:month, "must be the first day of the month") if month.present? && month.day != 1
  end
end
