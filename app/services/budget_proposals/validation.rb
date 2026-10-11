module BudgetProposals
  class Validation
    Result = Data.define(:errors, :warnings) do
      def valid?
        errors.empty?
      end
    end

    def self.call(proposal)
      new(proposal).call
    end

    def initialize(proposal)
      @proposal = proposal
    end

    def call
      errors = []
      payload = @proposal.proposal
      categories = payload["proposed_categories"]

      errors << "Proposal month does not match the proposal record." unless payload["month"] == @proposal.month.iso8601

      income = nonnegative_integer(payload, "available_paycheck_income_cents", "Total available income", errors)
      expenses = nonnegative_integer(payload, "proposed_expense_total_cents", "Total proposed expenses", errors)
      savings = nonnegative_integer(payload, "proposed_savings_cents", "Proposed savings", errors)
      validate_paycheck_income(payload, income, errors)
      validate_savings_allocations(payload["planned_savings_allocations"], savings, errors)

      if categories.is_a?(Array)
        validate_categories(categories, expenses, payload, errors)
      else
        errors << "Proposed categories are missing."
      end

      validate_exclusions(payload, errors)

      if income && expenses && savings && expenses + savings > income
        errors << "Total assigned cannot exceed total available income."
      end

      Result.new(errors: errors.uniq, warnings: payload_warnings(payload))
    end

    private

    def validate_paycheck_income(payload, expected_income, errors)
      totals = payload["paycheck_income_monthly_totals_cents"]
      unless totals.is_a?(Hash)
        errors << "Six monthly paycheck totals are missing."
        return
      end

      expected_months = FinancialPlanning::BudgetProposalBuilder::PAYCHECK_HISTORY_MONTHS.downto(1)
        .map { |offset| @proposal.month.prev_month(offset).iso8601 }
      errors << "Paycheck history must contain the six explicit months before the proposal month." unless totals.keys == expected_months

      values = expected_months.filter_map do |month|
        value = totals[month]
        unless value.is_a?(Integer) && value >= 0
          errors << "Paycheck total for #{month} must be a non-negative whole number of cents."
          next
        end
        value
      end
      return unless values.length == expected_months.length

      average = values.sum.fdiv(values.length).round
      recorded_average = payload["paycheck_income_six_month_average_cents"]
      errors << "The six-month paycheck average does not equal the arithmetic mean of the monthly totals." unless recorded_average == average
      errors << "Available income does not equal the six-month paycheck average." unless expected_income == average
    end

    def nonnegative_integer(payload, key, label, errors)
      value = payload[key]
      unless value.is_a?(Integer) && value >= 0
        errors << "#{label} must be a non-negative whole number of cents."
        return
      end

      value
    end

    def validate_categories(rows, expected_total, payload, errors)
      category_ids = []
      calculated_total = 0
      recurring_totals = recurring_totals(payload["recurring_obligation_details"], errors)

      rows.each_with_index do |row, index|
        unless row.is_a?(Hash)
          errors << "Category assignment #{index + 1} is invalid."
          next
        end

        category_id = integer_value(row["category_id"])
        amount = row["proposed_cents"]
        category_ids << category_id if category_id

        errors << "Category assignment #{index + 1} has no valid category." unless valid_expense_category?(category_id)
        if amount.is_a?(Integer) && amount >= 0
          calculated_total += amount
        else
          errors << "Category assignment #{index + 1} must have a non-negative whole number of cents."
        end

        validate_category_calculation(row, category_id, amount, recurring_totals, index, errors)
      end

      errors << "A category can only be assigned once." if category_ids.compact.uniq.length != category_ids.compact.length
      if expected_total && calculated_total != expected_total
        errors << "Category assignments do not equal the proposed expense total."
      end


      recurring_totals.each do |category_id, recurring_total|
        row = rows.find { |candidate| integer_value(candidate["category_id"]) == category_id }
        unless row && row["recurring_obligation_cents"] == recurring_total
          errors << "Known recurring obligations for category #{category_id} are not represented exactly once."
        end
      end
    end

    def validate_category_calculation(row, category_id, amount, recurring_totals, index, errors)
      basis = row["calculation_basis"]
      recurring = row["recurring_obligation_cents"]
      recurring = 0 unless recurring.is_a?(Integer)
      expected_recurring = recurring_totals.fetch(category_id, 0)

      if recurring != expected_recurring
        errors << "Category assignment #{index + 1} does not match its current recurring obligations."
      end

      if expected_recurring.positive?
        unless basis == "known_recurring_amount" && amount == expected_recurring
          errors << "Category assignment #{index + 1} must use the known current recurring amount without historical averaging."
        end
        return
      end

      case basis
      when "six_month_spending_average"
        average = row.dig("average_spending_cents", "6")
        unless average.is_a?(Integer) && amount == average
          errors << "Category assignment #{index + 1} must equal its six-month spending average."
        end
      when "same_month_last_year_plus_15_percent"
        prior_year = row["same_month_last_year_cents"]
        uplift = row["seasonal_utility_uplift_basis_points"]
        expected = if prior_year.is_a?(Integer) && uplift == FinancialPlanning::BudgetProposalBuilder::SEASONAL_UTILITY_UPLIFT_BASIS_POINTS
          (prior_year * (10_000 + uplift) / 10_000.0).round
        end
        unless expected && amount == expected
          errors << "Category assignment #{index + 1} must equal the same month last year plus 15%."
        end
      else
        errors << "Category assignment #{index + 1} has no recognized calculation basis."
      end
    end

    def recurring_totals(details, errors)
      unless details.is_a?(Array)
        errors << "Recurring obligation details are missing."
        return {}
      end

      details.each_with_object(Hash.new(0)) do |detail, totals|
        unless detail.is_a?(Hash)
          errors << "A recurring obligation detail is invalid."
          next
        end

        category_id = integer_value(detail["category_id"])
        amount = detail["projected_monthly_cents"]
        expense = RecurringExpense.find_by(id: detail["recurring_expense_id"])
        if category_id.nil? || !amount.is_a?(Integer) || amount <= 0 || expense.nil? || expense.active == false
          errors << "A recurring obligation detail is not backed by an active RecurringExpense."
          next
        end

        occurrence_count = FinancialPlanning::Schedule.dates(expense, from: @proposal.month, to: @proposal.month.end_of_month).length
        current_amount = occurrence_count * expense.estimated_amount_cents
        unless expense.category_id == category_id && amount == current_amount && detail["amount_per_occurrence_cents"] == expense.estimated_amount_cents
          errors << "RecurringExpense ##{expense.id} no longer matches the proposal's recurring amount."
          next
        end

        totals[category_id] += amount
      end
    end

    def validate_exclusions(payload, errors)
      exclusions = payload["exclusions"]
      unless exclusions.is_a?(Hash) && exclusions["transfer_kinds"] == TransactionClassification::TRANSFER_KINDS
        errors << "Transfer and credit-card-payment exclusions are missing."
      end
    end

    def validate_savings_allocations(rows, expected_total, errors)
      return if rows.nil?

      unless rows.is_a?(Array)
        errors << "Planned savings allocations are invalid."
        return
      end

      calculated_total = rows.each_with_index.sum do |row, index|
        unless row.is_a?(Hash) && row["name"].present? && row["proposed_cents"].is_a?(Integer) && row["proposed_cents"] >= 0
          errors << "Planned savings allocation #{index + 1} is invalid."
          next 0
        end

        row["proposed_cents"]
      end

      if expected_total && calculated_total != expected_total
        errors << "Planned savings allocations do not equal proposed savings."
      end
    end

    def integer_value(value)
      Integer(value, exception: false)
    end

    def valid_expense_category?(category_id)
      return false unless category_id

      Category.where(id: category_id, kind: "expense")
        .where.not(name: FinancialPlanning::BudgetProposalBuilder::NON_BUDGET_CATEGORY_NAMES)
        .exists?
    end

    def payload_warnings(payload)
      Array(payload["validation_warnings"]) + Array(payload["warnings"])
    end
  end
end
