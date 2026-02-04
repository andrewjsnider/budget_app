class Category < ApplicationRecord
  validates :name, presence: true
  validates :kind, inclusion: { in: %w[income expense] }
end
