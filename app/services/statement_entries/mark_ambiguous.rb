module StatementEntries
  class MarkAmbiguous
    def self.call(entry:, evidence:)
      StatementEntry.transaction do
        entry.lock!
        return entry if entry.resolution_status == "ambiguous"
        raise MatchExisting::InvalidMatch, "Only unresolved parsed entries can become ambiguous" unless entry.parsed? && entry.resolution_status == "unresolved"

        now = Time.current
        entry.update!(resolution_status: "ambiguous", ledger_transaction: nil, ignored_reason: nil, resolved_at: nil)
        entry.statement_entry_resolutions.create!(
          action: "marked_ambiguous",
          decision_source: "automatic",
          evidence: evidence,
          resolved_at: now
        )
        entry
      end
    end
  end
end
