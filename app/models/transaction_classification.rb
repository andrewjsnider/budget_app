class TransactionClassification < ApplicationRecord
  TRANSFER_KINDS = %w[internal_transfer savings_transfer credit_card_payment].freeze
  KINDS = (TRANSFER_KINDS + %w[refund reimbursement windfall]).freeze

  belongs_to :ledger_transaction, class_name: "Transaction", foreign_key: :transaction_id, inverse_of: :transaction_classification
  belongs_to :paired_transaction, class_name: "Transaction", optional: true

  validates :transaction_id, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :source, presence: true
  validate :pair_fields_match_kind

  scope :transfers, -> { where(kind: TRANSFER_KINDS) }

  private

  def pair_fields_match_kind
    if TRANSFER_KINDS.include?(kind)
      errors.add(:paired_transaction, "is required for a transfer") unless paired_transaction
      errors.add(:group_key, "is required for a transfer") if group_key.blank?
    elsif paired_transaction_id.present? || group_key.present?
      errors.add(:base, "Non-transfer classifications cannot have transfer pairing fields")
    end
    errors.add(:paired_transaction, "must differ from the transaction") if paired_transaction_id == transaction_id
  end
end
