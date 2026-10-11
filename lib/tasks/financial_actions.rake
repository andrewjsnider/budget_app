require "json"

module FinancialActionTaskOutput
  def self.print(result, json:, labels:)
    if json
      puts JSON.pretty_generate(result)
    else
      labels.each { |key, label| puts "#{label}: #{result.fetch(key)}" }
    end
  end
end

namespace :budget do
  desc "Categorize explicit transactions or apply existing payee rules"
  task categorize: :environment do
    abort "INPUT is required" if ENV["INPUT"].blank?
    result = FinancialActions::CategorizeTransactions.call(
      input: FinancialActions::InputFile.call(ENV.fetch("INPUT")),
      dry_run: ENV["DRY_RUN"] == "1"
    )
    FinancialActionTaskOutput.print(result, json: ENV["JSON"] == "1", labels: {
      categorized: "Categorized",
      skipped: "Skipped",
      ambiguous: "Ambiguous",
      failed: "Failed"
    })
  rescue FinancialActions::InputFile::InvalidInput,
         MonthlyProcessing::PathSafety::UnsafePath => e
    abort e.message
  end

  desc "Create or update reviewed payee rules"
  task manage_payee_rules: :environment do
    abort "INPUT is required" if ENV["INPUT"].blank?
    result = FinancialActions::ManagePayeeRules.call(
      input: FinancialActions::InputFile.call(ENV.fetch("INPUT")),
      dry_run: ENV["DRY_RUN"] == "1",
      confirmation: ENV["CONFIRM"]
    )
    FinancialActionTaskOutput.print(result, json: ENV["JSON"] == "1", labels: {
      created: "Created",
      updated: "Updated",
      skipped: "Skipped",
      ambiguous: "Ambiguous",
      failed: "Failed"
    })
  rescue FinancialActions::InputFile::InvalidInput,
         MonthlyProcessing::PathSafety::UnsafePath => e
    abort e.message
  end

  desc "Classify reviewed transfer, refund, reimbursement, or windfall transactions"
  task classify_transactions: :environment do
    abort "INPUT is required" if ENV["INPUT"].blank?
    result = FinancialActions::ClassifyTransactions.call(
      input: FinancialActions::InputFile.call(ENV.fetch("INPUT")),
      dry_run: ENV["DRY_RUN"] == "1"
    )
    FinancialActionTaskOutput.print(result, json: ENV["JSON"] == "1", labels: {
      classified: "Classified",
      skipped: "Skipped",
      ambiguous: "Ambiguous",
      failed: "Failed"
    })
  rescue FinancialActions::InputFile::InvalidInput,
         MonthlyProcessing::PathSafety::UnsafePath => e
    abort e.message
  end

  desc "Create or update recurring expenses from reviewed structured input"
  task manage_recurring_expenses: :environment do
    abort "INPUT is required" if ENV["INPUT"].blank?
    result = FinancialActions::ManageRecurringExpenses.call(
      input: FinancialActions::InputFile.call(ENV.fetch("INPUT")),
      dry_run: ENV["DRY_RUN"] == "1"
    )
    FinancialActionTaskOutput.print(result, json: ENV["JSON"] == "1", labels: {
      created: "Created",
      updated: "Updated",
      skipped: "Skipped",
      ambiguous: "Ambiguous",
      failed: "Failed"
    })
  rescue FinancialActions::InputFile::InvalidInput,
         MonthlyProcessing::PathSafety::UnsafePath => e
    abort e.message
  end

  desc "Build a deterministic next-month budget draft without finalizing a budget"
  task propose_budget: :environment do
    abort "MONTH is required and must use YYYY-MM" if ENV["MONTH"].blank?
    month = Date.strptime(ENV.fetch("MONTH"), "%Y-%m").beginning_of_month
    result = FinancialPlanning::BudgetProposalBuilder.call(
      month: month,
      dry_run: ENV["DRY_RUN"] == "1"
    )
    if ENV["JSON"] == "1"
      puts JSON.pretty_generate(result)
    else
      proposal = result.fetch(:proposal)
      puts "Budget proposal: #{proposal.fetch(:month)}"
      puts "Status: draft"
      puts "Recurring outside income: #{proposal.fetch(:recurring_outside_income_cents)} cents"
      puts "Proposed expenses: #{proposal.fetch(:proposed_expense_total_cents)} cents"
      puts "Buffer: #{proposal.fetch(:buffer_cents)} cents"
      puts "Proposed savings: #{proposal.fetch(:proposed_savings_cents)} cents"
      puts "Persisted: #{result.fetch(:persisted)}"
    end
  rescue Date::Error, ActiveRecord::RecordInvalid => e
    abort e.message
  end

  desc "Print deterministic financial context for one persisted budget proposal"
  task proposal_context: :environment do
    abort "PROPOSAL_ID is required" if ENV["PROPOSAL_ID"].blank?
    proposal = BudgetProposal.find(ENV.fetch("PROPOSAL_ID"))
    puts JSON.pretty_generate(proposal.agent_financial_context)
  rescue ActiveRecord::RecordNotFound
    abort "Budget proposal was not found"
  end

  desc "Store reviewed AI savings suggestions on a draft budget proposal"
  task store_savings_recommendations: :environment do
    abort "INPUT is required" if ENV["INPUT"].blank?
    result = FinancialActions::StoreBudgetProposalSavingsRecommendations.call(
      input: FinancialActions::InputFile.call(ENV.fetch("INPUT")),
      dry_run: ENV["DRY_RUN"] == "1"
    )
    if ENV["JSON"] == "1"
      puts JSON.pretty_generate(result)
    else
      puts "Proposal: #{result.fetch(:proposal_id)}"
      puts "Status: #{result.fetch(:proposal_status)}"
      puts "Recommendations: #{result.fetch(:recommendation_count)}"
      puts "Persisted: #{!result.fetch(:dry_run)}"
    end
  rescue FinancialActions::InputFile::InvalidInput,
         MonthlyProcessing::PathSafety::UnsafePath => e
    abort e.message
  end
end
