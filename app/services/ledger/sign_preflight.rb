module Ledger
  class SignPreflight
    def call
      report = base_report
      inspect_transactions(report)
      inspect_schedules(report)
      inspect_budget_uniqueness(report)
      report[:safe_to_normalize] = report[:ambiguous_records].empty?
      report
    end

    def self.call
      new.call
    end

    def self.normalization_completed?
      connection = ActiveRecord::Base.connection
      connection.data_source_exists?("ledger_normalizations") &&
        LedgerNormalization.exists?(key: LedgerNormalization::SIGNED_LEDGER_V1)
    end

    def self.format(report)
      lines = []
      lines << "Signed ledger preflight"
      lines << "Normalization state: #{report[:normalization_state]}"
      lines << "Transactions: #{report[:total_transaction_count]}"
      lines << "Transaction counts by category kind: #{report[:transaction_counts_by_category_kind].inspect}"
      lines << "Positive transaction counts by category kind: #{report[:positive_amounts_by_category_kind].inspect}"
      lines << "Positive cents by category kind: #{report[:positive_cents_by_category_kind].inspect}"
      lines << "Negative transaction counts by category kind: #{report[:negative_amounts_by_category_kind].inspect}"
      lines << "Negative cents by category kind: #{report[:negative_cents_by_category_kind].inspect}"
      lines << "Zero amounts: #{report[:zero_amount_transaction_ids].size} #{report[:zero_amount_transaction_ids].inspect}"
      lines << "Starting balances: #{report[:starting_balance_transaction_ids].size} #{report[:starting_balance_transaction_ids].inspect}"
      lines << "Missing account: #{report[:missing_account_transaction_ids].inspect}"
      lines << "Missing category: #{report[:missing_category_transaction_ids].inspect}"
      lines << "Missing date: #{report[:missing_date_transaction_ids].inspect}"
      lines << "Recurring expense sign inconsistencies: #{report[:recurring_expense_sign_inconsistency_ids].inspect}"
      lines << "Income estimate sign inconsistencies: #{report[:income_estimate_sign_inconsistency_ids].inspect}"
      lines << "Planned transaction sign changes: #{report.dig(:planned_changes, :transactions).size}"
      lines << "Planned recurring expense changes: #{report.dig(:planned_changes, :recurring_expenses).size}"
      lines << "Planned income estimate changes: #{report.dig(:planned_changes, :income_estimates).size}"
      lines << "Legacy conversion rule: preserve starting balances; negate positive non-starting expense transactions; preserve positive income and already-negative expenses."

      if report[:ambiguous_records].empty?
        lines << "Result: safe to normalize"
      else
        lines << "Result: STOP - ambiguous or invalid records require review"
        report[:ambiguous_records].each do |item|
          lines << "  - #{item[:type]} #{item[:id]}: #{item[:reason]}"
        end
      end

      lines.join("\n")
    end

    private

    def base_report
      {
        normalization_state: self.class.normalization_completed? ? "completed" : "legacy",
        total_transaction_count: Transaction.count,
        transaction_counts_by_category_kind: empty_kind_counts,
        positive_amounts_by_category_kind: empty_kind_counts,
        positive_cents_by_category_kind: empty_kind_counts,
        negative_amounts_by_category_kind: empty_kind_counts,
        negative_cents_by_category_kind: empty_kind_counts,
        zero_amount_transaction_ids: [],
        starting_balance_transaction_ids: [],
        missing_account_transaction_ids: [],
        missing_category_transaction_ids: [],
        missing_date_transaction_ids: [],
        recurring_expense_sign_inconsistency_ids: [],
        income_estimate_sign_inconsistency_ids: [],
        duplicate_budget_months: [],
        duplicate_budget_items: [],
        planned_changes: {
          transactions: [],
          recurring_expenses: [],
          income_estimates: []
        },
        ambiguous_records: []
      }
    end

    def empty_kind_counts
      { "income" => 0, "expense" => 0, "unknown" => 0 }
    end

    def inspect_transactions(report)
      completed = report[:normalization_state] == "completed"

      Transaction.includes(:account, :category).order(:id).each do |transaction|
        kind = %w[income expense].include?(transaction.category&.kind) ? transaction.category.kind : "unknown"
        report[:transaction_counts_by_category_kind][kind] += 1
        if transaction.amount_cents.to_i.positive?
          report[:positive_amounts_by_category_kind][kind] += 1
          report[:positive_cents_by_category_kind][kind] += transaction.amount_cents
        elsif transaction.amount_cents.to_i.negative?
          report[:negative_amounts_by_category_kind][kind] += 1
          report[:negative_cents_by_category_kind][kind] += transaction.amount_cents
        end

        record_missing_fields(report, transaction)
        report[:starting_balance_transaction_ids] << transaction.id if transaction.starting_balance?

        if transaction.amount_cents.to_i.zero?
          report[:zero_amount_transaction_ids] << transaction.id
          add_ambiguity(report, "Transaction", transaction.id, "amount is zero")
          next
        end

        next if completed
        next if transaction.starting_balance? && inspect_starting_balance(report, transaction)

        if kind == "expense" && transaction.amount_cents.positive?
          add_planned_change(report, :transactions, transaction, -transaction.amount_cents)
        elsif kind == "income" && transaction.amount_cents.negative?
          add_ambiguity(report, "Transaction", transaction.id, "negative amount in an income category is not safely interpretable under the legacy model")
        elsif kind == "unknown"
          add_ambiguity(report, "Transaction", transaction.id, "category kind is missing or invalid")
        end
      end
    end

    def record_missing_fields(report, transaction)
      if transaction.account_id.blank?
        report[:missing_account_transaction_ids] << transaction.id
        add_ambiguity(report, "Transaction", transaction.id, "account is missing")
      end
      if transaction.category_id.blank?
        report[:missing_category_transaction_ids] << transaction.id
        add_ambiguity(report, "Transaction", transaction.id, "category is missing")
      end
      if transaction.occurred_on.blank?
        report[:missing_date_transaction_ids] << transaction.id
        add_ambiguity(report, "Transaction", transaction.id, "date is missing")
      end
    end

    def inspect_starting_balance(report, transaction)
      if transaction.account&.kind == "credit" && transaction.amount_cents.positive?
        add_ambiguity(
          report,
          "Transaction",
          transaction.id,
          "positive credit-account starting balance could mean debt or a positive credit; set its canonical sign manually"
        )
      end
      true
    end

    def inspect_schedules(report)
      completed = report[:normalization_state] == "completed"

      RecurringExpense.order(:id).each do |expense|
        next if expense.estimated_amount_cents.to_i.positive?

        report[:recurring_expense_sign_inconsistency_ids] << expense.id
        if expense.estimated_amount_cents.to_i.zero? || completed
          add_ambiguity(report, "RecurringExpense", expense.id, "estimated amount must be a positive magnitude")
        else
          add_planned_change(report, :recurring_expenses, expense, expense.estimated_amount_cents.abs)
        end
      end

      IncomeEstimate.order(:id).each do |estimate|
        next if estimate.estimated_amount_cents.to_i.positive?

        report[:income_estimate_sign_inconsistency_ids] << estimate.id
        if estimate.estimated_amount_cents.to_i.zero? || completed
          add_ambiguity(report, "IncomeEstimate", estimate.id, "estimated amount must be a positive magnitude")
        else
          add_planned_change(report, :income_estimates, estimate, estimate.estimated_amount_cents.abs)
        end
      end
    end

    def inspect_budget_uniqueness(report)
      report[:duplicate_budget_months] = BudgetMonth.group(:month).having("COUNT(*) > 1").count.keys.compact.sort
      report[:duplicate_budget_items] = BudgetItem.group(:budget_month_id, :category_id).having("COUNT(*) > 1").count.keys.sort

      report[:duplicate_budget_months].each do |month|
        add_ambiguity(report, "BudgetMonth", month, "duplicate month prevents the required unique index")
      end
      report[:duplicate_budget_items].each do |key|
        add_ambiguity(report, "BudgetItem", key.join("/"), "duplicate month/category pair prevents the required unique index")
      end
    end

    def add_planned_change(report, collection, record, new_amount)
      report[:planned_changes][collection] << {
        id: record.id,
        from_cents: record.respond_to?(:estimated_amount_cents) ? record.estimated_amount_cents : record.amount_cents,
        to_cents: new_amount
      }
    end

    def add_ambiguity(report, type, id, reason)
      item = { type: type, id: id, reason: reason }
      report[:ambiguous_records] << item unless report[:ambiguous_records].include?(item)
    end
  end
end
