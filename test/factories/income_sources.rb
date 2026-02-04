FactoryBot.define do
  factory :income_source do
    name { "Job A" }
    kind { "w2" }
    active { true }
    association :account
    association :category, factory: :category
  end
end
