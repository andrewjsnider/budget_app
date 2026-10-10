module Statements
  class ReviewImport
    def self.call(statement_import:, opening_balance_cents: nil, entries: nil)
      new(statement_import: statement_import, opening_balance_cents: opening_balance_cents, entries: entries).call
    end

    def initialize(statement_import:, opening_balance_cents:, entries:)
      @statement_import = statement_import
      @opening_balance_cents = opening_balance_cents
      @entries = entries
    end

    def call
      entry_results = review_entries.map do |entry|
        entry_result(entry)
      end
      calculation = Reconciliations::StatementCalculator.call(
        statement_import: @statement_import,
        opening_balance_cents: @opening_balance_cents,
        entries: @entries
      )

      {
        statement_import_id: @statement_import.id,
        account: @statement_import.account.import_key,
        status: @statement_import.status,
        rows: entry_results.size,
        failed: entry_results.count { |entry| entry[:parse_status] == "failed" },
        matched: entry_results.count { |entry| entry[:matched_transaction_id].present? },
        new_transactions: entry_results.count { |entry| entry[:resolution_status] == "new_transaction" },
        unmatched: entry_results.count { |entry| entry[:resolution_status] == "unresolved" },
        ambiguous: entry_results.count { |entry| entry[:resolution_status] == "ambiguous" },
        ignored: entry_results.count { |entry| entry[:resolution_status] == "ignored" },
        opening_balance_cents: calculation.opening_balance_cents,
        activity_cents: calculation.activity_cents,
        statement_ending_balance_cents: calculation.statement_ending_balance_cents,
        computed_ending_balance_cents: calculation.computed_ending_balance_cents,
        difference_cents: calculation.difference_cents,
        previous_reconciliation_id: calculation.previous_reconciliation_id,
        ready_to_finalize: calculation.ready_to_finalize,
        blockers: calculation.blockers,
        entries: entry_results.select { |entry| entry[:parse_status] == "parsed" },
        failed_entries: entry_results.select { |entry| entry[:parse_status] == "failed" }
      }
    end

    private

    def review_entries
      return @entries.sort_by { |entry| [ entry.source_row_number, entry.id.to_i ] } if @entries

      @statement_import.statement_entries.includes(:ledger_transaction).order(:source_row_number, :id).to_a
    end

    def entry_result(entry)
      match_result = StatementEntries::Matcher.call(entry: entry)
      {
        entry_id: entry.id,
        source_row_number: entry.source_row_number,
        date: entry.posted_on || entry.transaction_on,
        description: entry.normalized_description.presence || entry.raw_description,
        amount_cents: entry.amount_cents,
        parse_status: entry.status,
        resolution_status: entry.resolution_status,
        matched_transaction_id: entry.transaction_id,
        candidate_transactions: match_result.fetch(:candidates),
        recommended_action: match_result.fetch(:recommended_action),
        evidence: {
          policy_version: match_result.fetch(:policy_version),
          classification: match_result.fetch(:classification)
        },
        error_code: entry.error_code,
        error_message: entry.error_message,
        ignored_reason: entry.ignored_reason
      }
    end
  end
end
