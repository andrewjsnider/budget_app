class AddApprovalToBudgetProposals < ActiveRecord::Migration[8.0]
  def change
    remove_check_constraint :budget_proposals, name: "budget_proposals_draft_only"
    add_check_constraint :budget_proposals,
      "status IN ('draft', 'applied')",
      name: "budget_proposals_status"

    add_reference :budget_proposals,
      :budget_month,
      foreign_key: { on_delete: :restrict },
      index: { unique: true }
    add_column :budget_proposals, :applied_at, :datetime

    add_check_constraint :budget_proposals,
      "(status = 'draft' AND budget_month_id IS NULL AND applied_at IS NULL) OR " \
        "(status = 'applied' AND budget_month_id IS NOT NULL AND applied_at IS NOT NULL)",
      name: "budget_proposals_application_fields"
  end
end
