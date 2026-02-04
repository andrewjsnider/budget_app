class Account < ApplicationRecord
  has_many :transactions, dependent: :restrict_with_error
  has_many :reconciliations, dependent: :destroy

  validates :name, presence: true
  validates :kind, inclusion: { in: %w[asset liability] }
end