module FinancialActions
  class StoreBudgetProposalSavingsRecommendations
    POLICY_VERSION = "budget-proposal-savings-recommendations-v1"
    CONFIDENCE_LEVELS = %w[low medium high].freeze
    REQUIRED_FIELDS = %w[
      title explanation current_spending_cents suggested_target_cents
      estimated_monthly_savings_cents estimated_annual_savings_cents confidence supporting_evidence
    ].freeze

    def self.call(input:, dry_run:)
      new(input:, dry_run:).call
    end

    def initialize(input:, dry_run:)
      @input = input
      @dry_run = dry_run
    end

    def call
      proposal = BudgetProposal.find(@input.fetch("proposal_id"))
      recommendations = @input.fetch("recommendations")
      raise InputFile::InvalidInput, "recommendations must be an array" unless recommendations.is_a?(Array)

      normalized = recommendations.map.with_index { |row, index| normalize(row, index:) }

      raise InputFile::InvalidInput, "Recommendations cannot be added to an applied proposal" if proposal.applied?

      proposal.with_lock do
        proposal.ai_savings_recommendations = normalized
        proposal.validate!
        proposal.save! unless @dry_run
      end

      {
        policy_version: POLICY_VERSION,
        dry_run: @dry_run,
        proposal_id: proposal.id,
        proposal_status: proposal.status,
        review_status: BudgetProposals::Validation.call(proposal).valid? ? "ready" : "invalid",
        recommendation_count: normalized.length,
        estimated_monthly_savings_cents: normalized.sum { |row| row.fetch("estimated_monthly_savings_cents") },
        estimated_annual_savings_cents: normalized.sum { |row| row.fetch("estimated_annual_savings_cents") },
        recommendations: normalized
      }
    rescue ActiveRecord::RecordNotFound
      raise InputFile::InvalidInput, "Budget proposal was not found"
    rescue KeyError => e
      raise InputFile::InvalidInput, "Missing required field: #{e.key}"
    rescue ActiveRecord::RecordInvalid => e
      raise InputFile::InvalidInput, e.record.errors.full_messages.to_sentence
    end

    private

    def normalize(row, index:)
      raise InputFile::InvalidInput, "Recommendation #{index + 1} must be an object" unless row.is_a?(Hash)

      missing = REQUIRED_FIELDS.reject { |field| row.key?(field) }
      if missing.any?
        raise InputFile::InvalidInput, "Recommendation #{index + 1} is missing: #{missing.join(', ')}"
      end

      confidence = row.fetch("confidence").to_s
      unless CONFIDENCE_LEVELS.include?(confidence)
        raise InputFile::InvalidInput, "Recommendation #{index + 1} confidence must be low, medium, or high"
      end

      evidence = Array(row.fetch("supporting_evidence")).map { |item| required_text(item, "supporting evidence", index:) }
      raise InputFile::InvalidInput, "Recommendation #{index + 1} requires supporting evidence" if evidence.empty?

      current_spending = nonnegative_integer(row.fetch("current_spending_cents"), "current spending", index:)
      suggested_target = nonnegative_integer(row.fetch("suggested_target_cents"), "suggested target", index:)
      monthly_savings = nonnegative_integer(row.fetch("estimated_monthly_savings_cents"), "estimated monthly savings", index:)
      annual_savings = nonnegative_integer(row.fetch("estimated_annual_savings_cents"), "estimated annual savings", index:)
      if suggested_target > current_spending
        raise InputFile::InvalidInput, "Recommendation #{index + 1} suggested target cannot exceed current spending"
      end
      if monthly_savings > current_spending - suggested_target
        raise InputFile::InvalidInput, "Recommendation #{index + 1} monthly savings cannot exceed the supported spending reduction"
      end

      {
        "title" => required_text(row.fetch("title"), "title", index:),
        "category_or_merchant" => optional_text(row["category_or_merchant"]),
        "explanation" => required_text(row.fetch("explanation"), "explanation", index:),
        "current_spending_cents" => current_spending,
        "suggested_target_cents" => suggested_target,
        "estimated_monthly_savings_cents" => monthly_savings,
        "estimated_annual_savings_cents" => annual_savings,
        "confidence" => confidence,
        "supporting_evidence" => evidence,
        "source" => row.fetch("source", "paperclip").to_s,
        "policy_version" => POLICY_VERSION,
        "generated_at" => row.fetch("generated_at", Time.current.iso8601).to_s
      }
    end

    def required_text(value, label, index:)
      text = value.to_s.strip
      raise InputFile::InvalidInput, "Recommendation #{index + 1} #{label} is required" if text.blank?

      text
    end

    def optional_text(value)
      value.to_s.strip.presence
    end

    def nonnegative_integer(value, label, index:)
      integer = Integer(value, exception: false)
      if integer.nil? || integer.negative?
        raise InputFile::InvalidInput, "Recommendation #{index + 1} #{label} must be a nonnegative integer"
      end

      integer
    end
  end
end
