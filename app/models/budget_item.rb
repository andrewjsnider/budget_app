class BudgetItem < ApplicationRecord
  belongs_to :budget_month
  belongs_to :category
end