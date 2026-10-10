FactoryBot.define do
  factory :budget_proposal do
    month { Date.current.next_month.beginning_of_month }
    status { "draft" }
    policy_version { BudgetProposal::POLICY_VERSION }
    sequence(:input_digest) { |number| Digest::SHA256.hexdigest("proposal-#{number}") }
    source { "test" }
    proposal { {} }
  end
end
