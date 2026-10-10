class AddFinancialActionBoundaries < ActiveRecord::Migration[8.0]
  def change
    create_table :transaction_classifications do |t|
      t.references :transaction, null: false, foreign_key: { on_delete: :restrict }, index: { unique: true }
      t.references :paired_transaction, foreign_key: { to_table: :transactions, on_delete: :restrict }
      t.string :kind, null: false
      t.string :group_key
      t.string :source, null: false, default: "paperclip"
      t.jsonb :evidence, null: false, default: {}
      t.timestamps
    end
    add_check_constraint :transaction_classifications,
      "kind IN ('internal_transfer', 'savings_transfer', 'credit_card_payment', 'refund', 'reimbursement', 'windfall')",
      name: "transaction_classifications_kind"

    add_column :recurring_expenses, :expense_type, :string, null: false, default: "other"
    add_column :recurring_expenses, :provenance, :jsonb, null: false, default: {}
    add_check_constraint :recurring_expenses,
      "expense_type IN ('subscription', 'utility', 'insurance', 'debt', 'essential', 'discretionary', 'other')",
      name: "recurring_expenses_expense_type"

    create_table :budget_proposals do |t|
      t.date :month, null: false
      t.string :status, null: false, default: "draft"
      t.string :policy_version, null: false
      t.string :input_digest, null: false
      t.string :source, null: false, default: "paperclip"
      t.jsonb :proposal, null: false, default: {}
      t.timestamps
    end
    add_index :budget_proposals, [ :month, :input_digest ], unique: true
    add_check_constraint :budget_proposals, "EXTRACT(day FROM month) = 1", name: "budget_proposals_month_first_day"
    add_check_constraint :budget_proposals, "status = 'draft'", name: "budget_proposals_draft_only"
    add_check_constraint :budget_proposals, "input_digest ~ '^[0-9a-f]{64}$'", name: "budget_proposals_input_digest"
  end
end
