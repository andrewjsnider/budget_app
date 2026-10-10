FactoryBot.define do
  factory :transaction do
    occurred_on { Date.current }
    description { "Test transaction" }
    amount_cents { -5000 }
    account_name { "Checking" }
    association :category
    association :account
  end
end
