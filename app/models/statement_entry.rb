class StatementEntry < ApplicationRecord
  STATUSES = %w[parsed failed].freeze
  RESOLUTION_STATUSES = %w[unresolved matched new_transaction ignored ambiguous].freeze

  belongs_to :statement_import
  belongs_to :ledger_transaction, class_name: "Transaction", foreign_key: :transaction_id, optional: true
  has_many :statement_entry_resolutions, dependent: :restrict_with_error

  validates :source_row_number, numericality: { only_integer: true, greater_than: 0 }
  validates :source_row_number, uniqueness: { scope: :statement_import_id }
  validates :source_identity,
            presence: true,
            format: { with: /\A[0-9a-f]{64}\z/ },
            uniqueness: true
  validates :raw_payload, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :resolution_status, inclusion: { in: RESOLUTION_STATUSES }, if: :parsed?
  validates :resolution_status, absence: true, if: :failed?
  validates :amount_cents, numericality: { only_integer: true }, allow_nil: true
  validate :status_fields_are_consistent
  validate :resolution_fields_are_consistent
  validate :reviewed_entry_is_immutable, on: :update

  def parsed?
    status == "parsed"
  end

  def failed?
    status == "failed"
  end

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

  def resolution_fields_are_consistent
    if failed?
      errors.add(:base, "A failed parser row cannot be resolved") if transaction_id.present? || ignored_reason.present? || resolved_at.present?
    elsif %w[matched new_transaction].include?(resolution_status)
      errors.add(:ledger_transaction, "is required for a linked resolution") if transaction_id.blank?
      errors.add(:resolved_at, "is required for a linked resolution") if resolved_at.blank?
      errors.add(:ignored_reason, "must be blank for a linked resolution") if ignored_reason.present?
    elsif resolution_status == "ignored"
      errors.add(:ledger_transaction, "must be blank when ignored") if transaction_id.present?
      errors.add(:ignored_reason, "is required when ignored") if ignored_reason.blank?
      errors.add(:resolved_at, "is required when ignored") if resolved_at.blank?
    elsif %w[unresolved ambiguous].include?(resolution_status)
      errors.add(:ledger_transaction, "must be blank while unresolved") if transaction_id.present?
      errors.add(:ignored_reason, "must be blank while unresolved") if ignored_reason.present?
      errors.add(:resolved_at, "must be blank while unresolved") if resolved_at.present?
    end
  end

  def reviewed_entry_is_immutable
    original_import_id = attribute_in_database("statement_import_id")
    return unless StatementImport.where(id: original_import_id, status: "reviewed").exists?

    protected_fields = %w[
      statement_import_id source_row_number source_transaction_id posted_on transaction_on
      raw_description normalized_description merchant_key amount_cents raw_payload source_identity
      status error_code error_message transaction_id resolution_status ignored_reason resolved_at
    ]
    changed_fields = changes_to_save.keys & protected_fields
    return if changed_fields.empty?

    errors.add(:base, "Statement entry cannot change after reconciliation is finalized")
  end
end
