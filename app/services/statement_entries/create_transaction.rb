module StatementEntries
  class CreateTransaction
    class InvalidCreation < StandardError; end

    def self.call(entry:, decision_source: "human")
      new(entry: entry, decision_source: decision_source).call
    end

    def initialize(entry:, decision_source:)
      @entry = entry
      @decision_source = decision_source
    end

    def call
      StatementEntry.transaction do
        @entry.lock!
        if @entry.resolution_status == "new_transaction" && @entry.ledger_transaction
          return @entry.ledger_transaction
        end

        validate!
        category_result = CategoryResolver.call(description: description, amount_cents: @entry.amount_cents)
        transaction = Transaction.create!(
          account: @entry.statement_import.account,
          category: category_result.category,
          occurred_on: statement_date,
          description: description,
          amount_cents: @entry.amount_cents,
          cleared: true
        )
        now = Time.current
        @entry.update!(
          ledger_transaction: transaction,
          resolution_status: "new_transaction",
          ignored_reason: nil,
          resolved_at: now
        )
        @entry.statement_entry_resolutions.create!(
          ledger_transaction: transaction,
          action: "created_transaction",
          decision_source: @decision_source,
          evidence: {
            date_policy: @entry.posted_on.present? ? "posted_on" : "transaction_on",
            payee_rule_id: category_result.payee_rule_id
          },
          resolved_at: now
        )
        transaction
      end
    end

    private

    def validate!
      raise InvalidCreation, "Only parsed statement entries can create transactions" unless @entry.parsed?
      raise InvalidCreation, "Reviewed statement entries cannot change" if @entry.statement_import.status == "reviewed"
      unless %w[unresolved ambiguous].include?(@entry.resolution_status)
        raise InvalidCreation, "Statement entry is already resolved as #{@entry.resolution_status}"
      end
      raise InvalidCreation, "Statement entry requires a date" unless statement_date
    end

    def statement_date
      @entry.posted_on || @entry.transaction_on
    end

    def description
      @entry.normalized_description.presence || @entry.raw_description.presence || "Statement row #{@entry.source_row_number}"
    end
  end
end
