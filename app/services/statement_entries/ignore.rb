module StatementEntries
  class Ignore
    class InvalidIgnore < StandardError; end

    def self.call(entry:, reason:)
      reason = reason.to_s.strip
      raise InvalidIgnore, "An explicit ignore reason is required" if reason.blank?

      StatementEntry.transaction do
        entry.lock!
        return entry if entry.resolution_status == "ignored" && entry.ignored_reason == reason
        unless entry.parsed? && %w[unresolved ambiguous].include?(entry.resolution_status)
          raise InvalidIgnore, "Only unresolved or ambiguous parsed entries can be ignored"
        end
        raise InvalidIgnore, "Reviewed statement entries cannot change" if entry.statement_import.status == "reviewed"

        now = Time.current
        entry.update!(
          resolution_status: "ignored",
          ledger_transaction: nil,
          ignored_reason: reason,
          resolved_at: now
        )
        entry.statement_entry_resolutions.create!(
          action: "ignored",
          decision_source: "human",
          reason: reason,
          resolved_at: now
        )
        entry
      end
    end
  end
end
