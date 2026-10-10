module StatementEntries
  class MatchExisting
    class InvalidMatch < StandardError; end

    def self.call(entry:, transaction:, decision_source: "human", reason: nil, evidence: {})
      new(
        entry: entry,
        transaction: transaction,
        decision_source: decision_source,
        reason: reason,
        evidence: evidence
      ).call
    end

    def initialize(entry:, transaction:, decision_source:, reason:, evidence:)
      @entry = entry
      @transaction = transaction
      @decision_source = decision_source
      @reason = reason
      @evidence = evidence
    end

    def call
      StatementEntry.transaction do
        @entry.lock!
        @transaction.lock!
        return @entry if @entry.resolution_status == "matched" && @entry.transaction_id == @transaction.id

        validate!
        now = Time.current
        @entry.update!(
          ledger_transaction: @transaction,
          resolution_status: "matched",
          ignored_reason: nil,
          resolved_at: now
        )
        @entry.statement_entry_resolutions.create!(
          ledger_transaction: @transaction,
          action: "matched_existing",
          decision_source: @decision_source,
          reason: @reason,
          evidence: @evidence,
          resolved_at: now
        )
        @entry
      end
    end

    private

    def validate!
      raise InvalidMatch, "Only parsed statement entries can be matched" unless @entry.parsed?
      raise InvalidMatch, "Reviewed statement entries cannot change" if @entry.statement_import.status == "reviewed"
      unless %w[unresolved ambiguous].include?(@entry.resolution_status)
        raise InvalidMatch, "Statement entry is already resolved as #{@entry.resolution_status}"
      end
      if @transaction.account_id != @entry.statement_import.account_id
        raise InvalidMatch, "Transaction account does not match the statement account"
      end
      if @transaction.amount_cents != @entry.amount_cents
        raise InvalidMatch, "Transaction amount does not match the signed statement amount"
      end

      conflict = @entry.statement_import.statement_entries
        .where(transaction_id: @transaction.id)
        .where.not(id: @entry.id)
        .exists?
      raise InvalidMatch, "Transaction is already linked to another entry in this statement" if conflict
    end
  end
end
