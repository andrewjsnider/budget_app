class MonthlyProcessingRun < ApplicationRecord
  STATUSES = %w[pending running completed blocked failed].freeze
  POLICY_VERSION = "monthly-processing-v1".freeze

  has_many :monthly_processing_run_statements, dependent: :restrict_with_error
  has_many :statement_imports, through: :monthly_processing_run_statements

  validates :month, :started_at, :input_digest, :policy_version, :source_root, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :input_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :month_is_first_day
  validate :terminal_run_has_completed_at
  validate :completed_run_is_immutable, on: :update

  def terminal?
    %w[completed blocked failed].include?(status)
  end

  private

  def month_is_first_day
    errors.add(:month, "must be the first day of a month") if month.present? && month.day != 1
  end

  def terminal_run_has_completed_at
    errors.add(:completed_at, "is required for a terminal run") if terminal? && completed_at.blank?
  end

  def completed_run_is_immutable
    return unless %w[completed blocked failed].include?(attribute_in_database("status"))
    return if changes_to_save.empty?

    errors.add(:base, "Completed monthly processing runs are immutable")
  end
end
