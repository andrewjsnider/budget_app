require "set"

module StatementEntries
  class Matcher
    POLICY_VERSION = "statement-match-v1".freeze
    DATE_WINDOW_DAYS = 3

    def self.call(entry:)
      new(entry: entry).call
    end

    def initialize(entry:)
      @entry = entry
    end

    def call
      return resolved_result unless @entry.parsed?
      return resolved_result unless %w[unresolved ambiguous].include?(@entry.resolution_status)

      candidates = candidate_transactions.map { |transaction| candidate_for(transaction) }
        .reject { |candidate| rejected_transaction_ids.include?(candidate.fetch(:transaction_id)) }
        .sort_by do |candidate|
          evidence = candidate.fetch(:evidence)
          [ evidence.fetch(:date_delta_days), evidence.fetch(:description_normalized_match) ? 0 : 1, candidate.fetch(:transaction_id) ]
        end
      eligible = candidates.reject { |candidate| candidate.dig(:evidence, :same_import_link_conflict) }
      strict = eligible.select { |candidate| candidate.dig(:evidence, :strict_policy_match) }

      if eligible.one? && strict.one?
        result("definite", "match_existing", candidates)
      elsif eligible.any?
        result("ambiguous", "review_ambiguous", candidates)
      else
        result("no_candidate", "create_new", candidates)
      end
    end

    private

    def candidate_transactions
      date = statement_date
      return Transaction.none unless date

      Transaction.where(
        account_id: @entry.statement_import.account_id,
        amount_cents: @entry.amount_cents,
        occurred_on: (date - DATE_WINDOW_DAYS.days)..(date + DATE_WINDOW_DAYS.days),
        starting_balance: false
      ).order(:occurred_on, :id)
    end

    def candidate_for(transaction)
      linked_entries = transaction.statement_entries.where.not(id: @entry.id).includes(:statement_import).to_a
      same_import_conflict = linked_entries.any? do |linked_entry|
        linked_entry.statement_import_id == @entry.statement_import_id
      end
      date_delta_days = entry_dates.map { |date| (transaction.occurred_on - date).to_i.abs }.min
      description_exact = DescriptionNormalizer.exact?(@entry.normalized_description, transaction.description)
      description_normalized_match = DescriptionNormalizer.match?(@entry.normalized_description, transaction.description)

      {
        transaction_id: transaction.id,
        occurred_on: transaction.occurred_on,
        description: transaction.description,
        amount_cents: transaction.amount_cents,
        evidence: {
          policy_version: POLICY_VERSION,
          same_account: true,
          amount_exact: true,
          date_delta_days: date_delta_days,
          description_exact: description_exact,
          description_normalized_match: description_normalized_match,
          transaction_already_linked: linked_entries.any?,
          linked_statement_entry_ids: linked_entries.map(&:id).sort,
          same_import_link_conflict: same_import_conflict,
          strict_policy_match: !same_import_conflict && (date_delta_days.zero? || description_normalized_match)
        }
      }
    end

    def entry_dates
      [ @entry.posted_on, @entry.transaction_on ].compact.uniq
    end

    def statement_date
      @entry.posted_on || @entry.transaction_on
    end

    def rejected_transaction_ids
      @rejected_transaction_ids ||= @entry.statement_entry_resolutions
        .where(action: "candidate_rejected")
        .where.not(transaction_id: nil)
        .pluck(:transaction_id)
        .to_set
    end

    def result(classification, recommended_action, candidates)
      {
        policy_version: POLICY_VERSION,
        classification: classification,
        recommended_action: recommended_action,
        candidates: candidates
      }
    end

    def resolved_result
      action = @entry.failed? ? "resolve_failed_row" : "already_resolved"
      result(@entry.failed? ? "parser_failed" : @entry.resolution_status, action, [])
    end
  end
end
