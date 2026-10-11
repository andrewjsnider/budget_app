class EnsureBudgetProposalBudgetLinkIsNotUnique < ActiveRecord::Migration[8.0]
  def up
    return unless index_exists?(:budget_proposals, :budget_month_id, unique: true)

    remove_index :budget_proposals, :budget_month_id
    add_index :budget_proposals, :budget_month_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Applied proposal audit records may share a budget month"
  end
end
