class Reconciliation < ApplicationRecord
  belongs_to :account
  belongs_to :statement_import, optional: true
  has_many :transactions, dependent: :restrict_with_error

  STATUSES = %w[draft finalized].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :starts_on, :ends_on, :statement_ending_balance_cents, presence: true
  validates :computed_ending_balance_cents, :difference_cents, presence: true, if: :finalized?
  validate :starts_on_is_not_after_ends_on
  validate :finalized_difference_is_zero
  validate :draft_is_not_reconciled
  validate :finalized_period_does_not_overlap
  validate :statement_import_matches_reconciliation
  validate :finalized_financial_fields_are_immutable, on: :update

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

  def statement_import_matches_reconciliation
    return if statement_import.nil?

    errors.add(:account, "must match the statement account") if account_id != statement_import.account_id
    errors.add(:starts_on, "must match the statement period") if starts_on != statement_import.started_on
    errors.add(:ends_on, "must match the statement period") if ends_on != statement_import.ended_on
    if statement_ending_balance_cents != statement_import.statement_ending_balance_cents
      errors.add(:statement_ending_balance_cents, "must match the statement import")
    end
  end

  def finalized_financial_fields_are_immutable
    return unless attribute_in_database("status") == "finalized"

    protected_fields = %w[
      account_id statement_import_id starts_on ends_on statement_ending_balance_cents
      starting_balance_cents computed_ending_balance_cents difference_cents status reconciled_at
    ]
    changed_fields = changes_to_save.keys & protected_fields
    return if changed_fields.empty?

    errors.add(:base, "Finalized reconciliation financial fields cannot change: #{changed_fields.join(', ')}")
  end
end
