class BudgetItem < ApplicationRecord
  belongs_to :budget_month
  belongs_to :category

  validates :category_id, uniqueness: { scope: :budget_month_id }
  validates :assigned_cents, numericality: { greater_than_or_equal_to: 0 }
end
