class LedgerNormalization < ApplicationRecord
  SIGNED_LEDGER_V1 = "signed-ledger-v1".freeze

  validates :key, presence: true, uniqueness: true
  validates :completed_at, presence: true
end
