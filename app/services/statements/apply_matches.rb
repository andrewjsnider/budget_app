module Statements
  class ApplyMatches
    def self.call(statement_import:)
      matched = 0
      ambiguous = 0

      statement_import.statement_entries.where(status: "parsed").order(:source_row_number, :id).each do |entry|
        next unless %w[unresolved ambiguous].include?(entry.resolution_status)

        result = StatementEntries::Matcher.call(entry: entry)
        case result.fetch(:classification)
        when "definite"
          candidate = result.fetch(:candidates).find { |item| item.dig(:evidence, :strict_policy_match) }
          transaction = Transaction.find(candidate.fetch(:transaction_id))
          StatementEntries::MatchExisting.call(
            entry: entry,
            transaction: transaction,
            decision_source: "automatic",
            reason: StatementEntries::Matcher::POLICY_VERSION,
            evidence: candidate.fetch(:evidence)
          )
          matched += 1
        when "ambiguous"
          StatementEntries::MarkAmbiguous.call(entry: entry, evidence: result)
          ambiguous += 1
        end
      end

      { matched: matched, ambiguous: ambiguous }
    end
  end
end
