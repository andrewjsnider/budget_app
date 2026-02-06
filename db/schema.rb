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

ActiveRecord::Schema[8.0].define(version: 2026_02_06_204417) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "name"
    t.string "kind"
    t.boolean "archived"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "budget_items", force: :cascade do |t|
    t.bigint "budget_month_id", null: false
    t.bigint "category_id", null: false
    t.integer "assigned_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_month_id"], name: "index_budget_items_on_budget_month_id"
    t.index ["category_id"], name: "index_budget_items_on_category_id"
  end

  create_table "budget_months", force: :cascade do |t|
    t.date "month"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["account_id"], name: "index_reconciliations_on_account_id"
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
    t.index ["account_id"], name: "index_recurring_expenses_on_account_id"
    t.index ["category_id"], name: "index_recurring_expenses_on_category_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.date "occurred_on"
    t.string "description"
    t.integer "amount_cents"
    t.string "account_name"
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.boolean "cleared"
    t.datetime "reconciled_at"
    t.boolean "starting_balance", default: false, null: false
    t.string "import_hash"
    t.index ["account_id", "import_hash"], name: "index_transactions_on_account_id_and_import_hash", unique: true
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["account_id"], name: "index_transactions_one_starting_balance_per_account", unique: true, where: "(starting_balance = true)"
    t.index ["category_id"], name: "index_transactions_on_category_id"
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
  add_foreign_key "income_estimates", "income_sources"
  add_foreign_key "income_sources", "accounts"
  add_foreign_key "income_sources", "categories"
  add_foreign_key "payee_rules", "categories"
  add_foreign_key "reconciliations", "accounts"
  add_foreign_key "recurring_expenses", "accounts"
  add_foreign_key "recurring_expenses", "categories"
  add_foreign_key "sessions", "users"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
end
