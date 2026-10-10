class StatementEntry < ApplicationRecord
  STATUSES = %w[parsed failed].freeze

  belongs_to :statement_import

  validates :source_row_number, numericality: { only_integer: true, greater_than: 0 }
  validates :source_row_number, uniqueness: { scope: :statement_import_id }
  validates :source_identity,
            presence: true,
            format: { with: /\A[0-9a-f]{64}\z/ },
            uniqueness: true
  validates :raw_payload, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { only_integer: true }, allow_nil: true
  validate :status_fields_are_consistent

  private

  def status_fields_are_consistent
    if status == "parsed"
      errors.add(:amount_cents, "is required for a parsed row") if amount_cents.nil?
      errors.add(:base, "A parsed row requires a posted or transaction date") if posted_on.nil? && transaction_on.nil?
      errors.add(:base, "A parsed row cannot have an error") if error_code.present? || error_message.present?
    elsif status == "failed"
      errors.add(:error_code, "is required for a failed row") if error_code.blank?
      errors.add(:error_message, "is required for a failed row") if error_message.blank?
    end
  end
end
