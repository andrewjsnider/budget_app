class BudgetMonth < ApplicationRecord
  has_many :budget_items, dependent: :destroy

  validates :month, presence: true, uniqueness: true
end
