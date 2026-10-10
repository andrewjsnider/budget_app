class Category < ApplicationRecord
  UTILITY_GROUP = "utilities"

  validates :name, presence: true
  validates :kind, inclusion: { in: %w[income expense] }

  scope :utility_expenses, -> {
    where(kind: "expense", group: UTILITY_GROUP, archived: [ false, nil ])
  }
end
