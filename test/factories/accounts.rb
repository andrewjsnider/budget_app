FactoryBot.define do
  factory :account do
    name { "Checking" }
    kind { "asset" }
    archived { false }
  end
end
