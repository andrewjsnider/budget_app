FactoryBot.define do
  factory :account do
    name { "Checking" }
    kind { "checking" }
    sequence(:import_key) { |number| "account-#{number}" }
    archived { false }
  end
end
