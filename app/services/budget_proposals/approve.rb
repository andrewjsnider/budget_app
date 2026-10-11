module BudgetProposals
  class Approve
    Result = Data.define(:success?, :budget_month, :errors, :existing_budget_month)

    def self.call(proposal)
      new(proposal).call
    end

    def initialize(proposal)
      @proposal = proposal
    end

    def call
      result = nil

      BudgetMonth.transaction do
        @proposal.lock!
        result = validate_and_apply
        raise ActiveRecord::Rollback unless result.success?
      end

      result
    rescue ActiveRecord::RecordInvalid => error
      failure(error.record.errors.full_messages)
    rescue ActiveRecord::RecordNotUnique
      existing = BudgetMonth.find_by(month: @proposal.month)
      failure([ "A budget already exists for #{@proposal.month.strftime('%B %Y')}." ], existing:)
    end

    private

    def validate_and_apply
      if @proposal.applied?
        return failure([ "This proposal has already been applied." ], existing: @proposal.budget_month)
      end

      if (existing = BudgetMonth.find_by(month: @proposal.month))
        return failure([ "A budget already exists for #{@proposal.month.strftime('%B %Y')}." ], existing:)
      end

      validation = Validation.call(@proposal)
      return failure(validation.errors) unless validation.valid?

      budget_month = BudgetMonth.create!(month: @proposal.month)
      @proposal.proposed_categories.each do |row|
        create_assignment!(budget_month, row)
      end
      @proposal.update!(status: "applied", budget_month:, applied_at: Time.current)

      Result.new(success?: true, budget_month:, errors: [], existing_budget_month: nil)
    end

    def create_assignment!(budget_month, row)
      budget_month.budget_items.create!(
        category_id: row.fetch("category_id"),
        assigned_cents: row.fetch("proposed_cents")
      )
    end

    def failure(errors, existing: nil)
      Result.new(success?: false, budget_month: nil, errors: Array(errors), existing_budget_month: existing)
    end
  end
end
