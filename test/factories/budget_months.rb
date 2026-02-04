FactoryBot.define do
  factory :budget_month do
    month { Date.current.beginning_of_month }
  end
end
