module Ledger
  class SignNormalizer
    CONFIRMATION = "normalize-signed-ledger-v1".freeze

    class ConfirmationRequired < StandardError; end
    class AmbiguousData < StandardError; end
    class MigrationRequired < StandardError; end

    def self.call(confirm:)
      new(confirm: confirm).call
    end

    def initialize(confirm:)
      @confirm = confirm
    end

    def call
      raise ConfirmationRequired, "Set CONFIRM=#{CONFIRMATION} to run normalization" unless @confirm == CONFIRMATION
      ensure_marker_table!

      existing = LedgerNormalization.find_by(key: LedgerNormalization::SIGNED_LEDGER_V1)
      return { status: :already_completed, changes: [] } if existing

      report = Ledger::SignPreflight.call
      unless report[:safe_to_normalize]
        raise AmbiguousData, Ledger::SignPreflight.format(report)
      end

      changes = []
      ApplicationRecord.transaction do
        now = Time.current
        normalize_transactions(report, changes, now)
        normalize_schedules(report, changes, now)
        LedgerNormalization.create!(
          key: LedgerNormalization::SIGNED_LEDGER_V1,
          completed_at: now,
          details: {
            transaction_changes: changes.count { |change| change[:type] == "Transaction" },
            recurring_expense_changes: changes.count { |change| change[:type] == "RecurringExpense" },
            income_estimate_changes: changes.count { |change| change[:type] == "IncomeEstimate" }
          }
        )
      end

      { status: :completed, changes: changes }
    end

    private

    def ensure_marker_table!
      return if ActiveRecord::Base.connection.data_source_exists?("ledger_normalizations")

      raise MigrationRequired, "Run bin/rails db:migrate after resolving all preflight blockers, then rerun normalization"
    end

    def normalize_transactions(report, changes, now)
      report.dig(:planned_changes, :transactions).each do |planned|
        transaction = Transaction.lock.find(planned[:id])
        ensure_unchanged!(transaction.amount_cents, planned)

        new_import_hash = if transaction.import_hash.present?
          Transactions::ImportFingerprint.call(
            account_id: transaction.account_id,
            occurred_on: transaction.occurred_on,
            description: transaction.description,
            amount_cents: planned[:to_cents]
          )
        end

        transaction.update_columns(
          amount_cents: planned[:to_cents],
          import_hash: new_import_hash,
          updated_at: now
        )
        changes << planned.merge(type: "Transaction")
      end
    end

    def normalize_schedules(report, changes, now)
      {
        recurring_expenses: RecurringExpense,
        income_estimates: IncomeEstimate
      }.each do |collection, model|
        report.dig(:planned_changes, collection).each do |planned|
          record = model.lock.find(planned[:id])
          ensure_unchanged!(record.estimated_amount_cents, planned)
          record.update_columns(estimated_amount_cents: planned[:to_cents], updated_at: now)
          changes << planned.merge(type: model.name)
        end
      end
    end

    def ensure_unchanged!(current_amount, planned)
      return if current_amount == planned[:from_cents]

      raise AmbiguousData, "Record #{planned[:id]} changed after preflight; rerun the preflight"
    end
  end
end
