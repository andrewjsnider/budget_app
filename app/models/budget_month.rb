class BudgetMonth < ApplicationRecord
  has_many :budget_items, dependent: :destroy
  has_one :budget_proposal, dependent: :restrict_with_error

  validates :month, presence: true, uniqueness: true
end
