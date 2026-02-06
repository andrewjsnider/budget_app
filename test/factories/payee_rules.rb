FactoryBot.define do
  factory :payee_rule do
    pattern { "COMCAST" }
    match_type { "contains" }
    active { true }

    association :category

    trait :starts_with do
      match_type { "starts_with" }
    end

    trait :regex do
      match_type { "regex" }
      pattern { "comcast|xfinity" }
    end

    trait :inactive do
      active { false }
    end
  end
end
