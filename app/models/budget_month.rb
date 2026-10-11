class BudgetMonth < ApplicationRecord
  has_many :budget_items, dependent: :destroy
  has_many :budget_proposals, dependent: :restrict_with_error

  validates :month, presence: true, uniqueness: true
  validates :planned_savings_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :planned_savings_allocations_are_valid

  private

  def planned_savings_allocations_are_valid
    return if planned_savings_allocations.is_a?(Array)

    errors.add(:planned_savings_allocations, "must be a list")
  end
end
