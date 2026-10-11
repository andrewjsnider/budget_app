class AddAiSavingsRecommendationsToBudgetProposals < ActiveRecord::Migration[8.0]
  def change
    add_column :budget_proposals, :ai_savings_recommendations, :jsonb, default: [], null: false
  end
end
