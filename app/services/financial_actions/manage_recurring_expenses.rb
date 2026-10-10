module FinancialActions
  class ManageRecurringExpenses
    ATTRIBUTES = %w[cadence interval weekday day_of_month estimated_amount_cents start_on end_on active expense_type].freeze

    def self.call(input:, dry_run:)
      new(input:, dry_run:).call
    end

    def initialize(input:, dry_run:)
      @input = input
      @dry_run = dry_run
    end

    def call
      rows = Array(@input["recurring_expenses"])
      raise InputFile::InvalidInput, "recurring_expenses must contain at least one action" if rows.empty?

      results = rows.map { |row| process(row) }
      counts = results.group_by { |row| row.fetch(:status) }.transform_values(&:count)
      {
        policy_version: "recurring-expenses-v1",
        dry_run: @dry_run,
        created: counts.fetch("created", 0),
        updated: counts.fetch("updated", 0),
        skipped: counts.fetch("skipped", 0),
        ambiguous: counts.fetch("ambiguous", 0),
        failed: counts.fetch("failed", 0),
        results: results
      }
    end

    private

    def process(row)
      account = ReferenceResolver.account(row.fetch("account"))
      category = ReferenceResolver.category(row.fetch("category"), kind: "expense")
      name = row.fetch("name").to_s.strip
      raise InputFile::InvalidInput, "name is required" if name.blank?
      existing = find_existing(row, account, name)
      return { status: "ambiguous", reason: "multiple_existing_expenses", name: name } if existing == :ambiguous

      expense = existing || RecurringExpense.new
      attrs = ATTRIBUTES.index_with { |attribute| parsed_attribute(attribute, row[attribute]) }
        .compact
        .merge(
          name: name,
          account: account,
          category: category,
          provenance: provenance(row)
        )
      expense.assign_attributes(attrs)
      expense.validate!
      action = existing.nil? ? "created" : (expense.changed? ? "updated" : "skipped")
      expense.save! unless @dry_run || action == "skipped"

      {
        status: action,
        recurring_expense_id: expense.id,
        name: name,
        account: account.import_key,
        category_id: category.id,
        expense_type: expense.expense_type,
        estimated_amount_cents: expense.estimated_amount_cents
      }
    rescue KeyError, Date::Error, InputFile::InvalidInput, ReferenceResolver::MissingReference,
           ReferenceResolver::AmbiguousReference, ActiveRecord::RecordInvalid => e
      { status: "failed", reason: e.message, name: row["name"] }
    end

    def find_existing(row, account, name)
      return RecurringExpense.find_by(id: row["id"]) if row["id"].present?

      matches = RecurringExpense.where(account: account).where("LOWER(name) = ?", name.downcase).limit(2).to_a
      return :ambiguous if matches.many?

      matches.first
    end

    def parsed_attribute(attribute, value)
      return nil if value.nil?
      return Date.iso8601(value) if %w[start_on end_on].include?(attribute)

      value
    end

    def provenance(row)
      row.fetch("provenance", {}).merge(
        "source" => row.fetch("source", "paperclip"),
        "policy_version" => "recurring-expenses-v1"
      )
    end
  end
end
