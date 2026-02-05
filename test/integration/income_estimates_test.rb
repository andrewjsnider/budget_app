require "test_helper"

class IncomeEstimatesTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user, password: "password123", password_confirmation: "password123")
    sign_in(@user)

    @account = FactoryBot.create(:account, name: "Checking", archived: false)
    @income_cat = FactoryBot.create(:category, name: "Job Income", kind: "income", group: "income", archived: false)
    @source = IncomeSource.create!(name: "Job A", kind: "w2", active: true, account: @account, category: @income_cat)
  end

  def test_index_renders
    get income_source_income_estimates_path(@source)
    assert_response :success
    assert_includes response.body, "Pay schedule"
  end

  def test_create_income_estimate
    assert_difference -> { @source.income_estimates.count }, 1 do
      post income_source_income_estimates_path(@source), params: {
        income_estimate: {
          cadence: "biweekly",
          interval: 1,
          weekday: 5,
          day_of_month: nil,
          estimated_amount_cents: 200_00,
          start_on: "2026-02-01",
          end_on: nil,
          active: true
        }
      }
    end

    assert_redirected_to income_source_income_estimates_path(@source)
  end

  def test_update_income_estimate
    est = @source.income_estimates.create!(
      cadence: "biweekly",
      interval: 1,
      weekday: 5,
      estimated_amount_cents: 200_00,
      start_on: Date.new(2026, 2, 1),
      active: true
    )

    patch income_source_income_estimate_path(@source, est), params: { income_estimate: { estimated_amount_cents: 250_00 } }
    assert_redirected_to income_source_income_estimates_path(@source)

    est.reload
    assert_equal 250_00, est.estimated_amount_cents
  end
end
