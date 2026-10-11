# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_10_11_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "name"
    t.string "kind"
    t.boolean "archived"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "import_key"
    t.index ["import_key"], name: "index_accounts_on_import_key", unique: true
    t.check_constraint "import_key IS NULL OR import_key::text ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::text", name: "accounts_import_key_format"
  end

  add_check_constraint "accounts", "archived IS TRUE OR import_key IS NOT NULL", name: "active_accounts_require_import_key", validate: false

  create_table "budget_items", force: :cascade do |t|
    t.bigint "budget_month_id", null: false
    t.bigint "category_id", null: false
    t.integer "assigned_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_month_id", "category_id"], name: "index_budget_items_on_budget_month_id_and_category_id", unique: true
    t.index ["budget_month_id"], name: "index_budget_items_on_budget_month_id"
    t.index ["category_id"], name: "index_budget_items_on_category_id"
  end

  create_table "budget_months", force: :cascade do |t|
    t.date "month"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["month"], name: "index_budget_months_on_month", unique: true
  end

  create_table "budget_proposals", force: :cascade do |t|
    t.date "month", null: false
    t.string "status", default: "draft", null: false
    t.string "policy_version", null: false
    t.string "input_digest", null: false
    t.string "source", default: "paperclip", null: false
    t.jsonb "proposal", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "budget_month_id"
    t.datetime "applied_at"
    t.index ["budget_month_id"], name: "index_budget_proposals_on_budget_month_id", unique: true
    t.index ["month", "input_digest"], name: "index_budget_proposals_on_month_and_input_digest", unique: true
    t.check_constraint "EXTRACT(day FROM month) = 1::numeric", name: "budget_proposals_month_first_day"
    t.check_constraint "input_digest::text ~ '^[0-9a-f]{64}$'::text", name: "budget_proposals_input_digest"
    t.check_constraint "status::text = 'draft'::text AND budget_month_id IS NULL AND applied_at IS NULL OR status::text = 'applied'::text AND budget_month_id IS NOT NULL AND applied_at IS NOT NULL", name: "budget_proposals_application_fields"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'applied'::character varying]::text[])", name: "budget_proposals_status"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.string "kind"
    t.string "group"
    t.boolean "archived"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "income_estimates", force: :cascade do |t|
    t.bigint "income_source_id", null: false
    t.string "cadence"
    t.integer "interval"
    t.integer "weekday"
    t.integer "day_of_month"
    t.integer "estimated_amount_cents"
    t.date "start_on"
    t.date "end_on"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["income_source_id"], name: "index_income_estimates_on_income_source_id"
  end

  create_table "income_sources", force: :cascade do |t|
    t.string "name"
    t.string "kind"
    t.boolean "active"
    t.bigint "account_id", null: false
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_income_sources_on_account_id"
    t.index ["category_id"], name: "index_income_sources_on_category_id"
  end

  create_table "ledger_normalizations", force: :cascade do |t|
    t.string "key", null: false
    t.datetime "completed_at", null: false
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_ledger_normalizations_on_key", unique: true
  end

  create_table "monthly_processing_run_statements", force: :cascade do |t|
    t.bigint "monthly_processing_run_id", null: false
    t.bigint "statement_import_id", null: false
    t.integer "position", null: false
    t.string "staging_status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["monthly_processing_run_id", "position"], name: "index_month_run_statements_on_run_and_position", unique: true
    t.index ["monthly_processing_run_id", "statement_import_id"], name: "index_month_run_statements_on_run_and_import", unique: true
    t.index ["monthly_processing_run_id"], name: "index_month_run_statements_on_run"
    t.index ["statement_import_id"], name: "index_month_run_statements_on_import"
    t.check_constraint "\"position\" >= 0", name: "monthly_processing_run_statements_position"
    t.check_constraint "staging_status::text = ANY (ARRAY['staged'::character varying, 'existing'::character varying]::text[])", name: "monthly_processing_run_statements_staging_status"
  end

  create_table "monthly_processing_runs", force: :cascade do |t|
    t.date "month", null: false
    t.string "status", null: false
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.boolean "dry_run", default: false, null: false
    t.string "input_digest", null: false
    t.string "policy_version", null: false
    t.text "source_root", null: false
    t.text "output_path"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["input_digest"], name: "index_monthly_processing_runs_on_input_digest"
    t.index ["month", "created_at"], name: "index_monthly_processing_runs_on_month_and_created_at"
    t.check_constraint "(status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying]::text[])) OR completed_at IS NOT NULL", name: "monthly_processing_runs_terminal_completed_at"
    t.check_constraint "EXTRACT(day FROM month) = 1::numeric", name: "monthly_processing_runs_month_first_day"
    t.check_constraint "input_digest::text ~ '^[0-9a-f]{64}$'::text", name: "monthly_processing_runs_input_digest"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'blocked'::character varying, 'failed'::character varying]::text[])", name: "monthly_processing_runs_status"
  end

  create_table "payee_rules", force: :cascade do |t|
    t.string "pattern", null: false
    t.string "match_type", default: "contains", null: false
    t.bigint "category_id", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "match_type"], name: "index_payee_rules_on_active_and_match_type"
    t.index ["category_id"], name: "index_payee_rules_on_category_id"
  end

  create_table "reconciliations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "starts_on"
    t.date "ends_on"
    t.integer "statement_ending_balance_cents"
    t.datetime "reconciled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "draft", null: false
    t.integer "starting_balance_cents"
    t.integer "computed_ending_balance_cents"
    t.integer "difference_cents"
    t.bigint "statement_import_id"
    t.index ["account_id", "starts_on", "ends_on"], name: "index_finalized_reconciliations_on_account_and_period", unique: true, where: "((status)::text = 'finalized'::text)"
    t.index ["account_id"], name: "index_reconciliations_on_account_id"
    t.index ["statement_import_id"], name: "index_reconciliations_on_statement_import_id", unique: true
    t.check_constraint "statement_import_id IS NULL OR starts_on IS NOT NULL AND ends_on IS NOT NULL AND statement_ending_balance_cents IS NOT NULL", name: "statement_reconciliations_require_statement_fields"
    t.check_constraint "status::text <> 'finalized'::text OR difference_cents = 0 AND reconciled_at IS NOT NULL", name: "reconciliations_finalized_exactly"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'finalized'::character varying]::text[])", name: "reconciliations_status"
  end

  create_table "recurring_expenses", force: :cascade do |t|
    t.string "name"
    t.boolean "active"
    t.bigint "account_id", null: false
    t.bigint "category_id", null: false
    t.string "cadence"
    t.integer "interval"
    t.integer "weekday"
    t.integer "day_of_month"
    t.integer "estimated_amount_cents"
    t.date "start_on"
    t.date "end_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "expense_type", default: "other", null: false
    t.jsonb "provenance", default: {}, null: false
    t.index ["account_id"], name: "index_recurring_expenses_on_account_id"
    t.index ["category_id"], name: "index_recurring_expenses_on_category_id"
    t.check_constraint "expense_type::text = ANY (ARRAY['subscription'::character varying, 'utility'::character varying, 'insurance'::character varying, 'debt'::character varying, 'essential'::character varying, 'discretionary'::character varying, 'other'::character varying]::text[])", name: "recurring_expenses_expense_type"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "statement_entries", force: :cascade do |t|
    t.bigint "statement_import_id", null: false
    t.integer "source_row_number", null: false
    t.string "source_transaction_id"
    t.date "posted_on"
    t.date "transaction_on"
    t.text "raw_description"
    t.text "normalized_description"
    t.string "merchant_key"
    t.integer "amount_cents"
    t.jsonb "raw_payload", default: {}, null: false
    t.string "source_identity", null: false
    t.string "status", null: false
    t.string "error_code"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "transaction_id"
    t.string "resolution_status"
    t.text "ignored_reason"
    t.datetime "resolved_at"
    t.index ["source_identity"], name: "index_statement_entries_on_source_identity", unique: true
    t.index ["source_transaction_id"], name: "index_statement_entries_on_source_transaction_id"
    t.index ["statement_import_id", "source_row_number"], name: "index_statement_entries_on_import_and_row", unique: true
    t.index ["statement_import_id", "transaction_id"], name: "index_statement_entries_on_import_and_transaction", unique: true, where: "(transaction_id IS NOT NULL)"
    t.index ["statement_import_id"], name: "index_statement_entries_on_statement_import_id"
    t.index ["transaction_id"], name: "index_statement_entries_on_transaction_id"
    t.check_constraint "source_identity::text ~ '^[0-9a-f]{64}$'::text", name: "statement_entries_source_identity_format"
    t.check_constraint "source_row_number > 0", name: "statement_entries_positive_row_number"
    t.check_constraint "status::text = 'failed'::text AND resolution_status IS NULL AND transaction_id IS NULL AND ignored_reason IS NULL AND resolved_at IS NULL OR status::text = 'parsed'::text AND ((resolution_status::text = ANY (ARRAY['unresolved'::character varying, 'ambiguous'::character varying]::text[])) AND transaction_id IS NULL AND ignored_reason IS NULL AND resolved_at IS NULL OR (resolution_status::text = ANY (ARRAY['matched'::character varying, 'new_transaction'::character varying]::text[])) AND transaction_id IS NOT NULL AND ignored_reason IS NULL AND resolved_at IS NOT NULL OR resolution_status::text = 'ignored'::text AND transaction_id IS NULL AND ignored_reason IS NOT NULL AND resolved_at IS NOT NULL)", name: "statement_entries_resolution_fields"
    t.check_constraint "status::text = 'parsed'::text AND amount_cents IS NOT NULL AND (posted_on IS NOT NULL OR transaction_on IS NOT NULL) AND error_code IS NULL AND error_message IS NULL OR status::text = 'failed'::text AND error_code IS NOT NULL AND error_message IS NOT NULL", name: "statement_entries_status_fields"
    t.check_constraint "status::text = ANY (ARRAY['parsed'::character varying, 'failed'::character varying]::text[])", name: "statement_entries_status"
  end

  create_table "statement_entry_resolutions", force: :cascade do |t|
    t.bigint "statement_entry_id", null: false
    t.bigint "transaction_id"
    t.string "action", null: false
    t.string "decision_source", null: false
    t.text "reason"
    t.jsonb "evidence", default: {}, null: false
    t.datetime "resolved_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["statement_entry_id"], name: "index_statement_entry_resolutions_on_statement_entry_id"
    t.index ["transaction_id"], name: "index_statement_entry_resolutions_on_transaction_id"
    t.check_constraint "action::text <> 'ignored'::text OR reason IS NOT NULL", name: "statement_entry_resolutions_ignore_reason"
    t.check_constraint "action::text = ANY (ARRAY['matched_existing'::character varying, 'created_transaction'::character varying, 'ignored'::character varying, 'marked_ambiguous'::character varying, 'candidate_rejected'::character varying]::text[])", name: "statement_entry_resolutions_action"
    t.check_constraint "decision_source::text = ANY (ARRAY['automatic'::character varying, 'human'::character varying]::text[])", name: "statement_entry_resolutions_source"
  end

  create_table "statement_imports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "source_filename", null: false
    t.string "source_path", null: false
    t.string "file_sha256", null: false
    t.string "parser_key", null: false
    t.string "parser_version", null: false
    t.date "started_on"
    t.date "ended_on"
    t.integer "statement_ending_balance_cents"
    t.string "status", null: false
    t.integer "row_count", default: 0, null: false
    t.integer "parsed_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "file_sha256"], name: "index_statement_imports_on_account_id_and_file_sha256", unique: true
    t.index ["account_id"], name: "index_statement_imports_on_account_id"
    t.check_constraint "file_sha256::text ~ '^[0-9a-f]{64}$'::text", name: "statement_imports_file_sha256_format"
    t.check_constraint "row_count >= 0 AND parsed_count >= 0 AND failed_count >= 0 AND row_count = (parsed_count + failed_count)", name: "statement_imports_consistent_counts"
    t.check_constraint "source_path::text !~ '(^|/)\\.\\.(/|$)'::text AND \"left\"(source_path::text, 1) <> '/'::text", name: "statement_imports_relative_source_path"
    t.check_constraint "status::text = ANY (ARRAY['staged'::character varying, 'failed'::character varying, 'reviewed'::character varying, 'superseded'::character varying]::text[])", name: "statement_imports_status"
  end

  create_table "transaction_classifications", force: :cascade do |t|
    t.bigint "transaction_id", null: false
    t.bigint "paired_transaction_id"
    t.string "kind", null: false
    t.string "group_key"
    t.string "source", default: "paperclip", null: false
    t.jsonb "evidence", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["paired_transaction_id"], name: "index_transaction_classifications_on_paired_transaction_id"
    t.index ["transaction_id"], name: "index_transaction_classifications_on_transaction_id", unique: true
    t.check_constraint "kind::text = ANY (ARRAY['internal_transfer'::character varying, 'savings_transfer'::character varying, 'credit_card_payment'::character varying, 'refund'::character varying, 'reimbursement'::character varying, 'windfall'::character varying]::text[])", name: "transaction_classifications_kind"
  end

  create_table "transactions", force: :cascade do |t|
    t.date "occurred_on", null: false
    t.string "description"
    t.integer "amount_cents", null: false
    t.string "account_name"
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.boolean "cleared"
    t.datetime "reconciled_at"
    t.boolean "starting_balance", default: false, null: false
    t.string "import_hash"
    t.bigint "reconciliation_id"
    t.index ["account_id", "import_hash"], name: "index_transactions_on_account_id_and_import_hash", unique: true
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["account_id"], name: "index_transactions_one_starting_balance_per_account", unique: true, where: "(starting_balance = true)"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["reconciliation_id"], name: "index_transactions_on_reconciliation_id"
    t.check_constraint "amount_cents <> 0", name: "transactions_amount_cents_nonzero"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "budget_items", "budget_months"
  add_foreign_key "budget_items", "categories"
  add_foreign_key "budget_proposals", "budget_months", on_delete: :restrict
  add_foreign_key "income_estimates", "income_sources"
  add_foreign_key "income_sources", "accounts"
  add_foreign_key "income_sources", "categories"
  add_foreign_key "monthly_processing_run_statements", "monthly_processing_runs", on_delete: :restrict
  add_foreign_key "monthly_processing_run_statements", "statement_imports", on_delete: :restrict
  add_foreign_key "payee_rules", "categories"
  add_foreign_key "reconciliations", "accounts"
  add_foreign_key "reconciliations", "statement_imports", on_delete: :restrict
  add_foreign_key "recurring_expenses", "accounts"
  add_foreign_key "recurring_expenses", "categories"
  add_foreign_key "sessions", "users"
  add_foreign_key "statement_entries", "statement_imports", on_delete: :restrict
  add_foreign_key "statement_entries", "transactions", on_delete: :restrict
  add_foreign_key "statement_entry_resolutions", "statement_entries", on_delete: :restrict
  add_foreign_key "statement_entry_resolutions", "transactions", on_delete: :restrict
  add_foreign_key "statement_imports", "accounts", on_delete: :restrict
  add_foreign_key "transaction_classifications", "transactions", column: "paired_transaction_id", on_delete: :restrict
  add_foreign_key "transaction_classifications", "transactions", on_delete: :restrict
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "reconciliations", on_delete: :restrict
end
