class Account < ApplicationRecord
  has_many :transactions, dependent: :restrict_with_error
  has_many :reconciliations, dependent: :destroy

  validates :name, presence: true
  validates :kind, inclusion: { in: %w[checking savings credit cash] }

  def balance_cents(as_of: nil)
    scope = transactions
    scope = scope.where("occurred_on <= ?", as_of) if as_of.present?
    scope.sum(:amount_cents)
  end

  def has_starting_balance?
    transactions.where(starting_balance: true).exists?
  end
end
