module BudgetProposals
  class Approve
    Result = Data.define(:success?, :replaced?, :budget_month, :errors, :existing_budget_month)

    def self.call(proposal, replace_existing: false)
      new(proposal, replace_existing:).call
    end

    def initialize(proposal, replace_existing: false)
      @proposal = proposal
      @replace_existing = replace_existing
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

      validation = Validation.call(@proposal)
      return failure(validation.errors) unless validation.valid?

      existing = BudgetMonth.lock.find_by(month: @proposal.month)
      if existing && !@replace_existing
        return failure([ "Confirm that you want to replace the existing #{@proposal.month.strftime('%B %Y')} budget." ], existing:)
      end

      replaced = existing.present?
      budget_month = existing || BudgetMonth.create!(month: @proposal.month)
      budget_month.budget_items.delete_all if replaced
      @proposal.proposed_categories.each do |row|
        create_assignment!(budget_month, row)
      end
      budget_month.update!(
        planned_savings_cents: @proposal.proposed_savings_cents,
        planned_savings_allocations: @proposal.planned_savings_allocations
      )

      applied_at = Time.current
      @proposal.update!(
        status: "applied",
        budget_month:,
        applied_at:,
        replaced_existing_budget: replaced,
        replaced_at: replaced ? applied_at : nil
      )

      Result.new(success?: true, replaced?: replaced, budget_month:, errors: [], existing_budget_month: nil)
    end

    def create_assignment!(budget_month, row)
      budget_month.budget_items.create!(
        category_id: row.fetch("category_id"),
        assigned_cents: row.fetch("proposed_cents")
      )
    end

    def failure(errors, existing: nil)
      Result.new(success?: false, replaced?: false, budget_month: nil, errors: Array(errors), existing_budget_month: existing)
    end
  end
end
