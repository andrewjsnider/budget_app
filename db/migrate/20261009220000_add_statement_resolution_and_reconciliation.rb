class AddStatementResolutionAndReconciliation < ActiveRecord::Migration[8.0]
  def up
    add_reference :statement_entries, :transaction, foreign_key: { on_delete: :restrict }
    add_column :statement_entries, :resolution_status, :string
    add_column :statement_entries, :ignored_reason, :text
    add_column :statement_entries, :resolved_at, :datetime

    execute <<~SQL.squish
      UPDATE statement_entries
      SET resolution_status = 'unresolved'
      WHERE status = 'parsed'
    SQL

    add_index :statement_entries,
              [ :statement_import_id, :transaction_id ],
              unique: true,
              where: "transaction_id IS NOT NULL",
              name: "index_statement_entries_on_import_and_transaction"
    add_check_constraint :statement_entries,
                         <<~SQL.squish,
                           (status = 'failed' AND resolution_status IS NULL AND transaction_id IS NULL AND ignored_reason IS NULL AND resolved_at IS NULL)
                           OR
                           (status = 'parsed' AND (
                             (resolution_status IN ('unresolved', 'ambiguous') AND transaction_id IS NULL AND ignored_reason IS NULL AND resolved_at IS NULL)
                             OR
                             (resolution_status IN ('matched', 'new_transaction') AND transaction_id IS NOT NULL AND ignored_reason IS NULL AND resolved_at IS NOT NULL)
                             OR
                             (resolution_status = 'ignored' AND transaction_id IS NULL AND ignored_reason IS NOT NULL AND resolved_at IS NOT NULL)
                           ))
                         SQL
                         name: "statement_entries_resolution_fields"

    create_table :statement_entry_resolutions do |t|
      t.references :statement_entry, null: false, foreign_key: { on_delete: :restrict }
      t.references :transaction, foreign_key: { on_delete: :restrict }
      t.string :action, null: false
      t.string :decision_source, null: false
      t.text :reason
      t.jsonb :evidence, null: false, default: {}
      t.datetime :resolved_at, null: false

      t.timestamps
    end

    add_check_constraint :statement_entry_resolutions,
                         "action IN ('matched_existing', 'created_transaction', 'ignored', 'marked_ambiguous', 'candidate_rejected')",
                         name: "statement_entry_resolutions_action"
    add_check_constraint :statement_entry_resolutions,
                         "decision_source IN ('automatic', 'human')",
                         name: "statement_entry_resolutions_source"
    add_check_constraint :statement_entry_resolutions,
                         "action <> 'ignored' OR reason IS NOT NULL",
                         name: "statement_entry_resolutions_ignore_reason"

    add_reference :reconciliations,
                  :statement_import,
                  foreign_key: { on_delete: :restrict },
                  index: { unique: true }
    add_check_constraint :reconciliations,
                         <<~SQL.squish,
                           statement_import_id IS NULL
                           OR
                           (starts_on IS NOT NULL AND ends_on IS NOT NULL AND statement_ending_balance_cents IS NOT NULL)
                         SQL
                         name: "statement_reconciliations_require_statement_fields"
    add_check_constraint :reconciliations,
                         "status IN ('draft', 'finalized')",
                         name: "reconciliations_status"
    add_check_constraint :reconciliations,
                         "status <> 'finalized' OR (difference_cents = 0 AND reconciled_at IS NOT NULL)",
                         name: "reconciliations_finalized_exactly"
    add_index :reconciliations,
              [ :account_id, :starts_on, :ends_on ],
              unique: true,
              where: "status = 'finalized'",
              name: "index_finalized_reconciliations_on_account_and_period"
  end

  def down
    remove_index :reconciliations, name: "index_finalized_reconciliations_on_account_and_period"
    remove_check_constraint :reconciliations, name: "reconciliations_finalized_exactly"
    remove_check_constraint :reconciliations, name: "reconciliations_status"
    remove_check_constraint :reconciliations, name: "statement_reconciliations_require_statement_fields"
    remove_reference :reconciliations, :statement_import, foreign_key: true

    drop_table :statement_entry_resolutions

    remove_check_constraint :statement_entries, name: "statement_entries_resolution_fields"
    remove_index :statement_entries, name: "index_statement_entries_on_import_and_transaction"
    remove_column :statement_entries, :resolved_at
    remove_column :statement_entries, :ignored_reason
    remove_column :statement_entries, :resolution_status
    remove_reference :statement_entries, :transaction, foreign_key: true
  end
end
