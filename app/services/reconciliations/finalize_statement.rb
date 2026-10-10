module Reconciliations
  class FinalizeStatement
    class CannotFinalize < StandardError
      attr_reader :review

      def initialize(review)
        @review = review
        super("Cannot finalize reconciliation: #{review.fetch(:blockers).map { |item| item.fetch(:message) }.join('; ')}")
      end
    end

    def self.call(statement_import:, opening_balance_cents: nil)
      new(statement_import: statement_import, opening_balance_cents: opening_balance_cents).call
    end

    def initialize(statement_import:, opening_balance_cents:)
      @statement_import = statement_import
      @opening_balance_cents = opening_balance_cents
    end

    def call
      Reconciliation.transaction do
        @statement_import.lock!
        existing = @statement_import.reconciliation
        return finalized_result(existing, already_finalized: true) if existing&.finalized?

        entries = @statement_import.statement_entries.lock.order(:id).to_a
        transaction_ids = entries.filter_map(&:transaction_id).uniq
        Transaction.where(id: transaction_ids).lock.order(:id).load

        review = Statements::ReviewImport.call(
          statement_import: @statement_import,
          opening_balance_cents: @opening_balance_cents
        )
        raise CannotFinalize, review unless review.fetch(:ready_to_finalize)

        now = Time.current
        reconciliation = existing || @statement_import.account.reconciliations.new(statement_import: @statement_import)
        reconciliation.assign_attributes(
          starts_on: @statement_import.started_on,
          ends_on: @statement_import.ended_on,
          statement_ending_balance_cents: @statement_import.statement_ending_balance_cents,
          starting_balance_cents: review.fetch(:opening_balance_cents),
          computed_ending_balance_cents: review.fetch(:computed_ending_balance_cents),
          difference_cents: review.fetch(:difference_cents),
          status: "finalized",
          reconciled_at: now
        )
        reconciliation.save!

        if transaction_ids.any?
          Transaction.where(id: transaction_ids).update_all(
            cleared: true,
            reconciliation_id: reconciliation.id,
            reconciled_at: now,
            updated_at: now
          )
        end
        @statement_import.update!(status: "reviewed")
        finalized_result(reconciliation, already_finalized: false)
      end
    end

    private

    def finalized_result(reconciliation, already_finalized:)
      {
        status: already_finalized ? "already_finalized" : "finalized",
        reconciliation_id: reconciliation.id,
        statement_import_id: @statement_import.id,
        difference_cents: reconciliation.difference_cents,
        already_finalized: already_finalized
      }
    end
  end
end
