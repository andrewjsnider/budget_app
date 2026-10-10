module StatementEntries
  class RejectCandidate
    class InvalidRejection < StandardError; end

    def self.call(entry:, transaction:, reason:)
      reason = reason.to_s.strip
      raise InvalidRejection, "A rejection reason is required" if reason.blank?
      raise InvalidRejection, "Only parsed unresolved entries can reject candidates" unless entry.parsed? && %w[unresolved ambiguous].include?(entry.resolution_status)
      raise InvalidRejection, "Candidate account does not match the statement" if transaction.account_id != entry.statement_import.account_id
      raise InvalidRejection, "Reviewed statement entries cannot change" if entry.statement_import.status == "reviewed"

      existing = entry.statement_entry_resolutions.find_by(action: "candidate_rejected", ledger_transaction: transaction)
      return existing if existing

      entry.statement_entry_resolutions.create!(
        ledger_transaction: transaction,
        action: "candidate_rejected",
        decision_source: "human",
        reason: reason,
        evidence: Matcher.call(entry: entry),
        resolved_at: Time.current
      )
    end
  end
end
