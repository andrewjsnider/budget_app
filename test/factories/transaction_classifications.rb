FactoryBot.define do
  factory :transaction_classification do
    association :ledger_transaction, factory: :transaction
    kind { "windfall" }
    source { "test" }
    evidence { {} }
  end
end
