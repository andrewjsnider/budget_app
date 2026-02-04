class IncomeSource < ApplicationRecord
  belongs_to :account
  belongs_to :category

  has_many :income_estimates, dependent: :destroy

  validates :name, presence: true
  validates :kind, presence: true
end
