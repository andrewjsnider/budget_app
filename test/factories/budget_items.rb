FactoryBot.define do
  factory :budget_item do
    budget_month { nil }
    category { nil }
    assigned_cents { 1 }
  end
end
