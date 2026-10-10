FactoryBot.define do
  factory :reconciliation do
    association :account
    starts_on { Date.current.beginning_of_month }
    ends_on { Date.current.end_of_month }
    statement_ending_balance_cents { 0 }
    computed_ending_balance_cents { 0 }
    difference_cents { 0 }
    status { "finalized" }
    reconciled_at { Time.current }
  end
end
