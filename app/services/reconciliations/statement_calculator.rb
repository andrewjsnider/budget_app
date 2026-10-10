module Reconciliations
  class StatementCalculator
    Result = Data.define(
      :opening_balance_cents,
      :activity_cents,
      :computed_ending_balance_cents,
      :statement_ending_balance_cents,
      :difference_cents,
      :previous_reconciliation_id,
      :blockers,
      :ready_to_finalize
    )

    def self.call(statement_import:, opening_balance_cents: nil)
      new(statement_import: statement_import, opening_balance_cents: opening_balance_cents).call
    end

    def initialize(statement_import:, opening_balance_cents:)
      @statement_import = statement_import
      @account = statement_import.account
      @explicit_opening_balance_cents = opening_balance_cents
    end

    def call
      blockers = structural_blockers
      opening, previous_id = opening_balance
      blockers << blocker("missing_opening_balance", "First statement requires an explicit opening balance or an eligible starting-balance transaction") if opening.nil?

      activity = linked_transactions.sum(&:amount_cents)
      computed = opening.nil? ? nil : opening + activity
      statement_ending = @statement_import.statement_ending_balance_cents
      difference = statement_ending.nil? || computed.nil? ? nil : statement_ending - computed
      if difference && !difference.zero?
        blockers << blocker("nonzero_difference", "Reconciliation difference is #{difference} cents")
      end

      Result.new(
        opening_balance_cents: opening,
        activity_cents: activity,
        computed_ending_balance_cents: computed,
        statement_ending_balance_cents: statement_ending,
        difference_cents: difference,
        previous_reconciliation_id: previous_id,
        blockers: blockers,
        ready_to_finalize: blockers.empty?
      )
    end

    private

    def structural_blockers
      blockers = []
      failed_count = entries.count(&:failed?)
      unresolved_count = parsed_entries.count { |entry| entry.resolution_status == "unresolved" }
      ambiguous_count = parsed_entries.count { |entry| entry.resolution_status == "ambiguous" }

      blockers << blocker("failed_entries", "#{failed_count} statement entries failed parsing", count: failed_count) if failed_count.positive?
      blockers << blocker("unresolved_entries", "#{unresolved_count} statement entries are unresolved", count: unresolved_count) if unresolved_count.positive?
      blockers << blocker("ambiguous_entries", "#{ambiguous_count} statement entries are ambiguous", count: ambiguous_count) if ambiguous_count.positive?
      blockers << blocker("missing_statement_period", "Statement start and end dates are required") if @statement_import.started_on.nil? || @statement_import.ended_on.nil?
      if @statement_import.started_on && @statement_import.ended_on && @statement_import.started_on > @statement_import.ended_on
        blockers << blocker("invalid_statement_period", "Statement start date is after its end date")
      end
      if @statement_import.statement_ending_balance_cents.nil?
        blockers << blocker("missing_ending_balance", "Statement ending balance is required")
      end
      blockers << blocker("superseded_statement", "Superseded statements cannot be reconciled") if @statement_import.status == "superseded"

      validate_links(blockers)
      validate_overlaps(blockers)
      blockers
    end

    def validate_links(blockers)
      parsed_entries.each do |entry|
        next unless %w[matched new_transaction].include?(entry.resolution_status)

        transaction = entry.ledger_transaction
        if transaction.nil?
          blockers << blocker("missing_linked_transaction", "Entry #{entry.id} has no linked transaction", entry_id: entry.id)
          next
        end
        if transaction.account_id != @account.id
          blockers << blocker("linked_account_mismatch", "Entry #{entry.id} links to a different account", entry_id: entry.id)
        end
        if transaction.amount_cents != entry.amount_cents
          blockers << blocker("linked_amount_mismatch", "Entry #{entry.id} amount conflicts with transaction #{transaction.id}", entry_id: entry.id)
        end
        if transaction.reconciliation_id.present? && transaction.reconciliation&.statement_import_id != @statement_import.id
          blockers << blocker(
            "transaction_already_reconciled",
            "Transaction #{transaction.id} already belongs to reconciliation #{transaction.reconciliation_id}",
            transaction_id: transaction.id
          )
        end
      end
    end

    def validate_overlaps(blockers)
      return if @statement_import.started_on.nil? || @statement_import.ended_on.nil?

      overlap = @account.reconciliations
        .where(status: "finalized")
        .where.not(statement_import_id: @statement_import.id)
        .where("starts_on <= ? AND ends_on >= ?", @statement_import.ended_on, @statement_import.started_on)
        .order(:id)
        .first
      return unless overlap

      blockers << blocker(
        "overlapping_finalized_reconciliation",
        "Statement period overlaps finalized reconciliation #{overlap.id}; automatic supersession is not allowed",
        reconciliation_id: overlap.id
      )
    end

    def opening_balance
      return [ nil, nil ] if @statement_import.started_on.nil?

      previous = @account.reconciliations
        .where(status: "finalized")
        .where("ends_on < ?", @statement_import.started_on)
        .order(ends_on: :desc, id: :desc)
        .first
      return [ previous.statement_ending_balance_cents, previous.id ] if previous
      return [ @explicit_opening_balance_cents, nil ] unless @explicit_opening_balance_cents.nil?

      starting_balance = @account.transactions
        .where(starting_balance: true)
        .where("occurred_on <= ?", @statement_import.started_on)
        .order(:occurred_on, :id)
        .first
      [ starting_balance&.amount_cents, nil ]
    end

    def entries
      @entries ||= @statement_import.statement_entries.includes(ledger_transaction: :reconciliation).order(:source_row_number, :id).to_a
    end

    def parsed_entries
      @parsed_entries ||= entries.select(&:parsed?)
    end

    def linked_transactions
      parsed_entries.filter_map do |entry|
        entry.ledger_transaction if %w[matched new_transaction].include?(entry.resolution_status)
      end.uniq(&:id)
    end

    def blocker(code, message, details = {})
      { code: code, message: message }.merge(details)
    end
  end
end
