FactoryBot.define do
  factory :reconciliation do
    account { nil }
    starts_on { "2026-02-03" }
    ends_on { "2026-02-03" }
    statement_ending_balance_cents { 1 }
    reconciled_at { "2026-02-03 17:35:20" }
  end
end
