class StatementEntryResolution < ApplicationRecord
  ACTIONS = %w[matched_existing created_transaction ignored marked_ambiguous candidate_rejected].freeze
  DECISION_SOURCES = %w[automatic human].freeze

  belongs_to :statement_entry
  belongs_to :ledger_transaction, class_name: "Transaction", foreign_key: :transaction_id, optional: true

  validates :action, inclusion: { in: ACTIONS }
  validates :decision_source, inclusion: { in: DECISION_SOURCES }
  validates :resolved_at, presence: true
  validates :reason, presence: true, if: -> { action == "ignored" }

  before_update :prevent_mutation
  before_destroy :prevent_mutation

  private

  def prevent_mutation
    errors.add(:base, "Resolution audit records are append-only")
    throw :abort
  end
end
