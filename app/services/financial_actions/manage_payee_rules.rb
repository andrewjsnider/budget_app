module FinancialActions
  class ManagePayeeRules
    CONFIRMATION = "apply-payee-rules-v1"

    def self.call(input:, dry_run:, confirmation: nil)
      new(input:, dry_run:, confirmation:).call
    end

    def initialize(input:, dry_run:, confirmation:)
      @input = input
      @dry_run = dry_run
      @confirmation = confirmation
    end

    def call
      rows = Array(@input["rules"])
      raise InputFile::InvalidInput, "rules must contain at least one rule" if rows.empty?
      unless @dry_run || @confirmation == CONFIRMATION
        raise InputFile::InvalidInput, "Apply requires CONFIRM=#{CONFIRMATION} after reviewing the dry run"
      end

      results = rows.map { |row| process(row) }
      counts = results.group_by { |row| row.fetch(:status) }.transform_values(&:count)
      {
        policy_version: "manage-payee-rules-v1",
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
      pattern = row.fetch("pattern").to_s.strip
      match_type = row.fetch("match_type", "contains").to_s
      category = ReferenceResolver.category(row.fetch("category"))
      active = row.key?("active") ? row.fetch("active") : true
      validate_pattern!(pattern, match_type)
      existing = find_existing(row, pattern, match_type)
      return { status: "ambiguous", reason: "multiple_existing_rules", pattern: pattern } if existing == :ambiguous

      candidate = existing || PayeeRule.new
      candidate.assign_attributes(pattern:, match_type:, category:, active:)
      candidate.validate!
      affected_count = Transaction.where.not(description: nil).count { |transaction| candidate.matches?(transaction.description) }
      action = if existing.nil?
        "created"
      elsif !candidate.changed?
        "skipped"
      else
        "updated"
      end
      candidate.save! unless @dry_run || action == "skipped"

      {
        status: action,
        payee_rule_id: candidate.id,
        pattern: pattern,
        match_type: match_type,
        category_id: category.id,
        active: active,
        affected_transaction_count: affected_count
      }
    rescue KeyError, InputFile::InvalidInput, ReferenceResolver::MissingReference,
           ReferenceResolver::AmbiguousReference, ActiveRecord::RecordInvalid => e
      { status: "failed", reason: e.message, pattern: row["pattern"] }
    end

    def find_existing(row, pattern, match_type)
      return PayeeRule.find_by(id: row["id"]) if row["id"].present?

      matches = PayeeRule.where(match_type: match_type).where("LOWER(pattern) = ?", pattern.downcase).limit(2).to_a
      return :ambiguous if matches.many?

      matches.first
    end

    def validate_pattern!(pattern, match_type)
      raise InputFile::InvalidInput, "pattern is required" if pattern.blank?
      raise InputFile::InvalidInput, "unsupported match_type" unless PayeeRule::MATCH_TYPES.include?(match_type)
      Regexp.new(pattern) if match_type == "regex"
    rescue RegexpError => e
      raise InputFile::InvalidInput, "invalid regular expression: #{e.message}"
    end
  end
end
