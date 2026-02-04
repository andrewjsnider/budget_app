class Transaction < ApplicationRecord
  belongs_to :category

  validates :occurred_on, :amount_cents, presence: true
end
