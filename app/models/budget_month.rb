class BudgetMonth < ApplicationRecord
  has_many :budget_items, dependent: :destroy
end
