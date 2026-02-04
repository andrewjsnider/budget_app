class Reconciliation < ApplicationRecord
  belongs_to :account

  validates :starts_on, :ends_on, :statement_ending_balance_cents, presence: true
end
