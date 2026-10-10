class CreateStatementStaging < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :import_key, :string
    add_index :accounts, :import_key, unique: true
    add_check_constraint :accounts,
                         "import_key IS NULL OR import_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'",
                         name: "accounts_import_key_format"
    add_check_constraint :accounts,
                         "archived IS TRUE OR import_key IS NOT NULL",
                         name: "active_accounts_require_import_key",
                         validate: false

    create_table :statement_imports do |t|
      t.references :account, null: false, foreign_key: { on_delete: :restrict }
      t.string :source_filename, null: false
      t.string :source_path, null: false
      t.string :file_sha256, null: false
      t.string :parser_key, null: false
      t.string :parser_version, null: false
      t.date :started_on
      t.date :ended_on
      t.integer :statement_ending_balance_cents
      t.string :status, null: false
      t.integer :row_count, null: false, default: 0
      t.integer :parsed_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0

      t.timestamps
    end

    add_index :statement_imports, [ :account_id, :file_sha256 ], unique: true
    add_check_constraint :statement_imports,
                         "file_sha256 ~ '^[0-9a-f]{64}$'",
                         name: "statement_imports_file_sha256_format"
    add_check_constraint :statement_imports,
                         "status IN ('staged', 'failed', 'reviewed', 'superseded')",
                         name: "statement_imports_status"
    add_check_constraint :statement_imports,
                         "row_count >= 0 AND parsed_count >= 0 AND failed_count >= 0 AND row_count = parsed_count + failed_count",
                         name: "statement_imports_consistent_counts"

    create_table :statement_entries do |t|
      t.references :statement_import, null: false, foreign_key: { on_delete: :restrict }
      t.integer :source_row_number, null: false
      t.string :source_transaction_id
      t.date :posted_on
      t.date :transaction_on
      t.text :raw_description
      t.text :normalized_description
      t.string :merchant_key
      t.integer :amount_cents
      t.jsonb :raw_payload, null: false, default: {}
      t.string :source_identity, null: false
      t.string :status, null: false
      t.string :error_code
      t.text :error_message

      t.timestamps
    end

    add_index :statement_entries,
              [ :statement_import_id, :source_row_number ],
              unique: true,
              name: "index_statement_entries_on_import_and_row"
    add_index :statement_entries, :source_identity, unique: true
    add_index :statement_entries, :source_transaction_id
    add_check_constraint :statement_entries,
                         "source_row_number > 0",
                         name: "statement_entries_positive_row_number"
    add_check_constraint :statement_entries,
                         "source_identity ~ '^[0-9a-f]{64}$'",
                         name: "statement_entries_source_identity_format"
    add_check_constraint :statement_entries,
                         "status IN ('parsed', 'failed')",
                         name: "statement_entries_status"
    add_check_constraint :statement_entries,
                         <<~SQL.squish,
                           (status = 'parsed' AND amount_cents IS NOT NULL AND (posted_on IS NOT NULL OR transaction_on IS NOT NULL) AND error_code IS NULL AND error_message IS NULL)
                           OR
                           (status = 'failed' AND error_code IS NOT NULL AND error_message IS NOT NULL)
                         SQL
                         name: "statement_entries_status_fields"
  end
end
