class AddReplacementAuditAndSavingsToBudgets < ActiveRecord::Migration[8.0]
  def change
    add_column :budget_months, :planned_savings_cents, :integer, null: false, default: 0
    add_column :budget_months, :planned_savings_allocations, :jsonb, null: false, default: []

    add_column :budget_proposals, :replaced_existing_budget, :boolean, null: false, default: false
    add_column :budget_proposals, :replaced_at, :datetime
    remove_index :budget_proposals, :budget_month_id, unique: true
    add_index :budget_proposals, :budget_month_id
    add_check_constraint :budget_proposals,
      "(replaced_existing_budget = FALSE AND replaced_at IS NULL) OR " \
        "(status = 'applied' AND replaced_existing_budget = TRUE AND replaced_at IS NOT NULL)",
      name: "budget_proposals_replacement_audit"
  end
end
