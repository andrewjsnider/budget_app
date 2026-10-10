FactoryBot.define do
  factory :statement_entry do
    association :statement_import
    sequence(:source_row_number) { |number| number }
    posted_on { Date.new(2026, 10, 5) }
    raw_description { "SAFEWAY #1234 TACOMA WA" }
    normalized_description { raw_description }
    amount_cents { -5_000 }
    raw_payload { { "row" => source_row_number } }
    sequence(:source_identity) { |number| format("%064x", number) }
    status { "parsed" }
    resolution_status { "unresolved" }

    trait :failed do
      posted_on { nil }
      amount_cents { nil }
      status { "failed" }
      resolution_status { nil }
      error_code { "invalid_amount" }
      error_message { "Amount is invalid" }
    end
  end
end
