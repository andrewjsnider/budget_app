require "test_helper"

class FinancialActions::ManageRecurringExpensesTest < ActiveSupport::TestCase
  test "recurring expense creation uses positive magnitudes and is idempotent" do
    account = create(:account, import_key: "bills-checking")
    category = create(:category, name: "Electric", kind: "expense")
    input = {
      "recurring_expenses" => [
        {
          "name" => "Electric Company",
          "account" => account.import_key,
          "category" => category.id,
          "expense_type" => "utility",
          "cadence" => "monthly",
          "interval" => 1,
          "day_of_month" => 15,
          "estimated_amount_cents" => 12_500,
          "start_on" => "2026-01-01",
          "active" => true
        }
      ]
    }

    preview = nil
    assert_no_difference("RecurringExpense.count") do
      preview = FinancialActions::ManageRecurringExpenses.call(input:, dry_run: true)
    end
    first = FinancialActions::ManageRecurringExpenses.call(input:, dry_run: false)
    second = FinancialActions::ManageRecurringExpenses.call(input:, dry_run: false)

    assert_equal 1, preview[:created]
    assert_equal 1, first[:created]
    assert_equal 1, second[:skipped]
    expense = RecurringExpense.find_by!(name: "Electric Company")
    assert_equal 12_500, expense.estimated_amount_cents
    assert_equal "utility", expense.expense_type
    assert_equal "recurring-expenses-v1", expense.provenance.fetch("policy_version")
  end
end
