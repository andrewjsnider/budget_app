module FinancialPlanning
  class SavingsRecommendations
    Recommendation = Data.define(
      :category_name,
      :current_spending_cents,
      :current_spending_basis,
      :suggested_target_cents,
      :potential_monthly_savings_cents,
      :potential_annual_savings_cents,
      :explanation
    )

    def self.call(proposal)
      new(proposal).call
    end

    def initialize(proposal)
      @proposal = proposal
    end

    def call
      @proposal.proposed_categories.filter_map { |row| recommendation_for(row) }
        .sort_by { |recommendation| -recommendation.potential_monthly_savings_cents }
    end

    private

    def recommendation_for(row)
      averages = row["average_spending_cents"]
      return unless averages.is_a?(Hash)
      return if @proposal.savings_category_assignment?(row)
      return if row.fetch("recurring_obligation_cents", 0).to_i.positive?

      current = averages.fetch("3", 0).to_i
      target = averages.fetch("6", 0).to_i
      potential = current - target
      return unless target.positive? && potential.positive?

      name = row.fetch("category_name", "Category ##{row['category_id']}")
      Recommendation.new(
        category_name: name,
        current_spending_cents: current,
        current_spending_basis: "3-month average",
        suggested_target_cents: target,
        potential_monthly_savings_cents: potential,
        potential_annual_savings_cents: potential * 12,
        explanation: "Recent #{name.downcase} spending is above its six-month average."
      )
    end
  end
end
