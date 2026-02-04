class Transaction < ApplicationRecord
  belongs_to :category
  belongs_to :account, optional: true

  validates :occurred_on, :amount_cents, presence: true
end
