FactoryBot.define do
  factory :account do
    name { "Checking" }
    kind { "checking" }
    archived { false }
  end
end
