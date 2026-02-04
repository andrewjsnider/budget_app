FactoryBot.define do
  factory :income_estimate do
    cadence { "biweekly" }
    interval { 1 }
    weekday { 5 }
    day_of_month { nil }
    estimated_amount_cents { 200_00 }
    start_on { Date.current.beginning_of_month }
    end_on { nil }
    active { true }
    association :income_source
  end
end
