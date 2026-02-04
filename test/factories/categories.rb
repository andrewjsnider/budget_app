FactoryBot.define do
  factory :category do
    name { "Groceries" }
    kind { "expense" }
    group { "food" }
    archived { false }
  end
end
