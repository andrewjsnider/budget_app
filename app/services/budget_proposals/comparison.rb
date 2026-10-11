module BudgetProposals
  class Comparison
    Result = Data.define(
      :existing_income_cents,
      :proposal_income_cents,
      :existing_spending_cents,
      :proposal_spending_cents,
      :existing_savings_cents,
      :proposal_savings_cents,
      :existing_savings_rate,
      :proposal_savings_rate,
      :category_changes
    )
    CategoryChange = Data.define(:category_name, :existing_cents, :proposal_cents)

    def self.call(proposal, budget_month)
      new(proposal, budget_month).call
    end

    def initialize(proposal, budget_month)
      @proposal = proposal
      @budget_month = budget_month
    end

    def call
      existing_income = BudgetMonthSummary.new(@budget_month).income_cents

      Result.new(
        existing_income_cents: existing_income,
        proposal_income_cents: @proposal.proposed_income_cents,
        existing_spending_cents: @budget_month.budget_items.sum(:assigned_cents),
        proposal_spending_cents: @proposal.proposed_expense_cents,
        existing_savings_cents: @budget_month.planned_savings_cents,
        proposal_savings_cents: @proposal.proposed_savings_cents,
        existing_savings_rate: savings_rate(@budget_month.planned_savings_cents, existing_income),
        proposal_savings_rate: @proposal.savings_rate_percentage,
        category_changes: category_changes
      )
    end

    private

    def category_changes
      existing = @budget_month.budget_items.includes(:category).index_by(&:category_id)
      proposed = @proposal.proposed_categories.index_by { |row| row.fetch("category_id").to_i }

      (existing.keys | proposed.keys).filter_map do |category_id|
        existing_cents = existing[category_id]&.assigned_cents.to_i
        proposal_cents = proposed.dig(category_id, "proposed_cents").to_i
        next if existing_cents == proposal_cents

        CategoryChange.new(
          category_name: category_name(category_id, proposed, existing),
          existing_cents:,
          proposal_cents:
        )
      end.sort_by(&:category_name)
    end

    def savings_rate(savings_cents, income_cents)
      return 0.0 unless income_cents.positive?

      savings_cents.fdiv(income_cents) * 100
    end

    def category_name(category_id, proposed, existing)
      proposed.dig(category_id, "category_name") ||
        existing[category_id]&.category&.name ||
        Category.find_by(id: category_id)&.name ||
        "Category ##{category_id}"
    end
  end
end
