FactoryBot.define do
  factory :recurring_expense do
    name { "Sewer" }
    cadence { "monthly" }
    interval { 1 }
    day_of_month { 15 }
    weekday { nil }
    estimated_amount_cents { -75_00 }
    start_on { Date.current.beginning_of_month }
    end_on { nil }
    active { true }
    association :account
    association :category
  end
end
