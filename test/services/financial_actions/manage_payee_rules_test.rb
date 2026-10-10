require "test_helper"

class FinancialActions::ManagePayeeRulesTest < ActiveSupport::TestCase
  test "rule application is confirmed and idempotent with an affected preview" do
    category = create(:category, name: "Utilities")
    create(:transaction, description: "CITY WATER PAYMENT")
    input = {
      "rules" => [
        { "pattern" => "CITY WATER", "match_type" => "contains", "category" => category.id }
      ]
    }

    preview = FinancialActions::ManagePayeeRules.call(input:, dry_run: true)
    first = FinancialActions::ManagePayeeRules.call(
      input:,
      dry_run: false,
      confirmation: FinancialActions::ManagePayeeRules::CONFIRMATION
    )
    second = FinancialActions::ManagePayeeRules.call(
      input:,
      dry_run: false,
      confirmation: FinancialActions::ManagePayeeRules::CONFIRMATION
    )

    assert_equal 1, preview[:created]
    assert_equal 1, preview[:results].sole[:affected_transaction_count]
    assert_equal 1, first[:created]
    assert_equal 1, second[:skipped]
    assert_equal 1, PayeeRule.where(pattern: "CITY WATER").count
  end
end
