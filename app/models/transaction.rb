class Transaction < ApplicationRecord
  belongs_to :category
  belongs_to :account, optional: true

  before_destroy :ensure_not_reconciled

  validates :occurred_on, :amount_cents, presence: true

  private

  def ensure_not_reconciled
    if reconciled_at.present?
      errors.add(:base, "Cannot delete a reconciled transaction")
      throw :abort
    end
  end
end
