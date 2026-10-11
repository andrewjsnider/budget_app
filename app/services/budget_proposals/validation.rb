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

      income = nonnegative_integer(payload, "recurring_outside_income_cents", "Total available income", errors)
      expenses = nonnegative_integer(payload, "proposed_expense_total_cents", "Total proposed expenses", errors)
      savings = nonnegative_integer(payload, "proposed_savings_cents", "Proposed savings", errors)

      if categories.is_a?(Array)
        validate_categories(categories, expenses, errors)
      else
        errors << "Proposed categories are missing."
      end

      if income && expenses && savings && expenses + savings > income
        errors << "Total assigned cannot exceed total available income."
      end

      Result.new(errors: errors.uniq, warnings: payload_warnings(payload))
    end

    private

    def nonnegative_integer(payload, key, label, errors)
      value = payload[key]
      unless value.is_a?(Integer) && value >= 0
        errors << "#{label} must be a non-negative whole number of cents."
        return
      end

      value
    end

    def validate_categories(rows, expected_total, errors)
      category_ids = []
      calculated_total = 0

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
      end

      errors << "A category can only be assigned once." if category_ids.compact.uniq.length != category_ids.compact.length
      if expected_total && calculated_total != expected_total
        errors << "Category assignments do not equal the proposed expense total."
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
