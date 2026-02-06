class Transaction < ApplicationRecord
  belongs_to :category
  belongs_to :account, optional: true

  before_destroy :ensure_not_reconciled

  validates :occurred_on, :amount_cents, presence: true
  validate :only_one_starting_balance_per_account
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }

  private

  def ensure_not_reconciled
    if reconciled_at.present?
      errors.add(:base, "Cannot delete a reconciled transaction")
      throw :abort
    end
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
