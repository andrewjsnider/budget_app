class RecurringExpense < ApplicationRecord
  belongs_to :account
  belongs_to :category

  validates :name, presence: true
  validates :cadence, inclusion: { in: %w[weekly biweekly monthly quarterly yearly] }
  validates :interval, numericality: { greater_than_or_equal_to: 1 }
  validates :estimated_amount_cents, numericality: { other_than: 0 }
  validates :start_on, presence: true
end
