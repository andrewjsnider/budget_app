class HardenLedgerAndReconciliations < ActiveRecord::Migration[8.0]
  def up
    create_table :ledger_normalizations do |t|
      t.string :key, null: false
      t.datetime :completed_at, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_index :ledger_normalizations, :key, unique: true

    change_column_null :transactions, :account_id, false
    change_column_null :transactions, :occurred_on, false
    change_column_null :transactions, :amount_cents, false
    add_check_constraint :transactions, "amount_cents <> 0", name: "transactions_amount_cents_nonzero"

    add_index :budget_months, :month, unique: true
    add_index :budget_items, [ :budget_month_id, :category_id ], unique: true

    add_column :reconciliations, :status, :string, null: false, default: "draft"
    add_column :reconciliations, :starting_balance_cents, :integer
    add_column :reconciliations, :computed_ending_balance_cents, :integer
    add_column :reconciliations, :difference_cents, :integer

    execute <<~SQL.squish
      UPDATE reconciliations
      SET status = 'finalized',
          computed_ending_balance_cents = statement_ending_balance_cents,
          difference_cents = 0
      WHERE reconciled_at IS NOT NULL
    SQL

    add_reference :transactions, :reconciliation, foreign_key: { on_delete: :restrict }
  end

  def down
    remove_reference :transactions, :reconciliation, foreign_key: true

    remove_column :reconciliations, :difference_cents
    remove_column :reconciliations, :computed_ending_balance_cents
    remove_column :reconciliations, :starting_balance_cents
    remove_column :reconciliations, :status

    remove_index :budget_items, [ :budget_month_id, :category_id ]
    remove_index :budget_months, :month

    remove_check_constraint :transactions, name: "transactions_amount_cents_nonzero"
    change_column_null :transactions, :amount_cents, true
    change_column_null :transactions, :occurred_on, true
    change_column_null :transactions, :account_id, true

    drop_table :ledger_normalizations
  end
end
