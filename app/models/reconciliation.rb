class Reconciliation < ApplicationRecord
  belongs_to :account
  has_many :transactions, dependent: :restrict_with_error

  STATUSES = %w[draft finalized].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :starts_on, :ends_on, :statement_ending_balance_cents, presence: true
  validates :computed_ending_balance_cents, :difference_cents, presence: true, if: :finalized?
  validate :starts_on_is_not_after_ends_on
  validate :finalized_difference_is_zero
  validate :draft_is_not_reconciled
  validate :finalized_period_does_not_overlap

  def finalized?
    status == "finalized"
  end

  private

  def starts_on_is_not_after_ends_on
    return if starts_on.blank? || ends_on.blank? || starts_on <= ends_on

    errors.add(:ends_on, "must be on or after the start date")
  end

  def finalized_difference_is_zero
    return unless finalized?

    errors.add(:difference_cents, "must be zero to finalize") unless difference_cents == 0
    errors.add(:reconciled_at, "must be present when finalized") if reconciled_at.blank?
  end

  def draft_is_not_reconciled
    errors.add(:reconciled_at, "must be blank while draft") if status == "draft" && reconciled_at.present?
  end

  def finalized_period_does_not_overlap
    return unless finalized? && account_id.present? && starts_on.present? && ends_on.present?

    overlap = self.class.where(account_id: account_id, status: "finalized")
      .where.not(id: id)
      .where("starts_on <= ? AND ends_on >= ?", ends_on, starts_on)

    errors.add(:base, "Finalized reconciliation period overlaps an existing finalized reconciliation") if overlap.exists?
  end
end
