class CreateMonthlyProcessingRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :monthly_processing_runs do |t|
      t.date :month, null: false
      t.string :status, null: false
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.boolean :dry_run, null: false, default: false
      t.string :input_digest, null: false
      t.string :policy_version, null: false
      t.text :source_root, null: false
      t.text :output_path
      t.text :error_message

      t.timestamps
    end

    add_index :monthly_processing_runs, [ :month, :created_at ]
    add_index :monthly_processing_runs, :input_digest
    add_check_constraint :monthly_processing_runs,
                         "status IN ('pending', 'running', 'completed', 'blocked', 'failed')",
                         name: "monthly_processing_runs_status"
    add_check_constraint :monthly_processing_runs,
                         "EXTRACT(DAY FROM month) = 1",
                         name: "monthly_processing_runs_month_first_day"
    add_check_constraint :monthly_processing_runs,
                         "input_digest ~ '^[0-9a-f]{64}$'",
                         name: "monthly_processing_runs_input_digest"
    add_check_constraint :monthly_processing_runs,
                         "status IN ('pending', 'running') OR completed_at IS NOT NULL",
                         name: "monthly_processing_runs_terminal_completed_at"

    create_table :monthly_processing_run_statements do |t|
      t.references :monthly_processing_run,
                   null: false,
                   foreign_key: { on_delete: :restrict },
                   index: { name: "index_month_run_statements_on_run" }
      t.references :statement_import,
                   null: false,
                   foreign_key: { on_delete: :restrict },
                   index: { name: "index_month_run_statements_on_import" }
      t.integer :position, null: false
      t.string :staging_status, null: false

      t.timestamps
    end

    add_index :monthly_processing_run_statements,
              [ :monthly_processing_run_id, :statement_import_id ],
              unique: true,
              name: "index_month_run_statements_on_run_and_import"
    add_index :monthly_processing_run_statements,
              [ :monthly_processing_run_id, :position ],
              unique: true,
              name: "index_month_run_statements_on_run_and_position"
    add_check_constraint :monthly_processing_run_statements,
                         "position >= 0",
                         name: "monthly_processing_run_statements_position"
    add_check_constraint :monthly_processing_run_statements,
                         "staging_status IN ('staged', 'existing')",
                         name: "monthly_processing_run_statements_staging_status"
  end
end
