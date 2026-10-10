module FinancialActions
  class CategorizeTransactions
    def self.call(input:, dry_run:)
      new(input:, dry_run:).call
    end

    def initialize(input:, dry_run:)
      @input = input
      @dry_run = dry_run
    end

    def call
      mappings = Array(@input["mappings"])
      rule_ids = Array(@input["transaction_ids"]).map(&:to_i)
      apply_rules = @input["apply_payee_rules"] == true
      raise InputFile::InvalidInput, "Provide mappings or transaction_ids with apply_payee_rules=true" if mappings.empty? && (!apply_rules || rule_ids.empty?)

      mapping_groups = mappings.group_by { |row| row.fetch("transaction_id").to_i }
      target_ids = (mapping_groups.keys + (apply_rules ? rule_ids : [])).uniq.sort
      results = target_ids.map do |transaction_id|
        categorize_one(transaction_id, mapping_groups.fetch(transaction_id, []), apply_rules)
      end

      counts = results.group_by { |row| row.fetch(:status) }.transform_values(&:count)
      {
        policy_version: "categorize-transactions-v1",
        dry_run: @dry_run,
        categorized: counts.fetch("categorized", 0),
        skipped: counts.fetch("skipped", 0),
        ambiguous: counts.fetch("ambiguous", 0),
        failed: counts.fetch("failed", 0),
        results: results
      }
    end

    private

    def categorize_one(transaction_id, mappings, apply_rules)
      transaction = Transaction.includes(:category).find_by(id: transaction_id)
      return result(transaction_id, "failed", "transaction_not_found") unless transaction

      category, evidence = category_for(transaction, mappings, apply_rules)
      return result(transaction_id, evidence.fetch(:status), evidence.fetch(:reason), evidence: evidence) unless category
      if transaction.category_id == category.id
        return result(transaction_id, "skipped", "already_categorized", from_category_id: transaction.category_id, to_category_id: category.id, evidence: evidence)
      end
      if reconciled?(transaction)
        return result(transaction_id, "failed", "reconciled_transaction", from_category_id: transaction.category_id, to_category_id: category.id, evidence: evidence)
      end

      transaction.update!(category: category) unless @dry_run
      result(transaction_id, "categorized", @dry_run ? "would_categorize" : "categorized",
        from_category_id: transaction.category_id_before_last_save || transaction.category_id,
        to_category_id: category.id,
        evidence: evidence)
    rescue KeyError, ReferenceResolver::MissingReference, ReferenceResolver::AmbiguousReference,
           ActiveRecord::RecordInvalid => e
      result(transaction_id, "failed", e.message)
    end

    def category_for(transaction, mappings, apply_rules)
      if mappings.any?
        references = mappings.map { |row| row.fetch("category") }.uniq
        return [ nil, { status: "ambiguous", reason: "conflicting_explicit_mappings", category_references: references } ] if references.many?

        category = ReferenceResolver.category(references.sole)
        return [ category, { source: "explicit_mapping" } ]
      end

      return [ nil, { status: "skipped", reason: "no_explicit_mapping" } ] unless apply_rules

      rules = PayeeRule.where(active: true).includes(:category).order(:id).select do |rule|
        rule.matches?(transaction.description)
      end
      return [ nil, { status: "skipped", reason: "no_matching_payee_rule" } ] if rules.empty?

      category_ids = rules.map(&:category_id).uniq
      if category_ids.many?
        return [ nil, { status: "ambiguous", reason: "payee_rules_disagree", payee_rule_ids: rules.map(&:id) } ]
      end

      [ rules.first.category, { source: "payee_rule", payee_rule_ids: rules.map(&:id) } ]
    end

    def reconciled?(transaction)
      transaction.reconciled_at.present? || transaction.reconciliation_id.present?
    end

    def result(transaction_id, status, reason, **extra)
      { transaction_id: transaction_id, status: status, reason: reason }.merge(extra)
    end
  end
end
