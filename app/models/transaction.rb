class Transaction < ApplicationRecord
  belongs_to :category
  belongs_to :account
  belongs_to :reconciliation, optional: true
  has_many :statement_entries, dependent: :restrict_with_error
  has_many :statement_entry_resolutions, dependent: :restrict_with_error
  has_one :transaction_classification,
    foreign_key: :transaction_id,
    inverse_of: :ledger_transaction,
    dependent: :restrict_with_error

  before_destroy :ensure_not_reconciled

  validates :occurred_on, :amount_cents, presence: true
  validate :only_one_starting_balance_per_account
  validate :reconciled_financial_fields_are_immutable, on: :update
  validates :amount_cents, numericality: { other_than: 0 }

  scope :excluding_transfers, -> {
    where.not(id: TransactionClassification.transfers.select(:transaction_id))
  }

  PROTECTED_RECONCILED_FIELDS = %w[
    amount_cents occurred_on account_id import_hash starting_balance
    cleared reconciliation_id reconciled_at
  ].freeze

  private

  def ensure_not_reconciled
    if reconciled?
      errors.add(:base, "Cannot delete a reconciled transaction")
      throw :abort
    end
  end

  def reconciled_financial_fields_are_immutable
    return unless reconciled_in_database?

    changed_fields = changes_to_save.keys & PROTECTED_RECONCILED_FIELDS
    return if changed_fields.empty?

    errors.add(:base, "Cannot change reconciled financial fields: #{changed_fields.join(', ')}")
  end

  def reconciled?
    reconciled_at.present? || reconciliation_id.present?
  end

  def reconciled_in_database?
    attribute_in_database("reconciled_at").present? || attribute_in_database("reconciliation_id").present?
  end

  def only_one_starting_balance_per_account
    return unless starting_balance
    return if account_id.blank?

    existing = Transaction.where(account_id: account_id, starting_balance: true)
    existing = existing.where.not(id: id) if persisted?

    if existing.exists?
      errors.add(:starting_balance, "already exists for this account")
    end
  end
end
