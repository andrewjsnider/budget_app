require "digest"
require "json"

module FinancialPlanning
  class BudgetProposalBuilder
    BUFFER_BASIS_POINTS = 500
    HISTORY_WINDOWS = [ 3, 6, 12 ].freeze
    NON_BUDGET_CATEGORY_NAMES = [ "Uncategorized", "Credit Card Payments" ].freeze

    def self.call(month:, dry_run:, source: "paperclip")
      new(month:, dry_run:, source:).call
    end

    def initialize(month:, dry_run:, source:)
      @month = month.beginning_of_month
      @dry_run = dry_run
      @source = source
    end

    def call
      payload = build_payload
      digest = Digest::SHA256.hexdigest(JSON.generate(canonical(payload)))
      proposal = BudgetProposal.find_by(month: @month, input_digest: digest)
      unless @dry_run || proposal
        proposal = BudgetProposal.create!(
          month: @month,
          status: "draft",
          policy_version: BudgetProposal::POLICY_VERSION,
          input_digest: digest,
          source: @source,
          proposal: payload
        )
      end

      {
        policy_version: BudgetProposal::POLICY_VERSION,
        status: "draft",
        dry_run: @dry_run,
        persisted: proposal.present?,
        proposal_id: proposal&.id,
        input_digest: digest,
        proposal: payload
      }
    end

    private

    def build_payload
      recurring_income = recurring_income_cents
      obligations = recurring_obligations
      category_rows = proposed_categories(obligations)
      proposed_expenses = category_rows.sum { |row| row.fetch(:proposed_cents) }
      buffer = (recurring_income * BUFFER_BASIS_POINTS / 10_000.0).round
      savings = [ recurring_income - proposed_expenses - buffer, 0 ].max

      {
        month: @month.iso8601,
        planning_baseline: "recurring_outside_income",
        recurring_outside_income_cents: recurring_income,
        recurring_outside_income_monthly_totals_cents: recurring_outside_income_monthly_totals(6),
        total_outside_income_previous_month_cents: total_outside_income_for(@month.prev_month),
        outside_income_averages_cents: HISTORY_WINDOWS.to_h { |months| [ months.to_s, average_outside_income(months) ] },
        recurring_outside_income_averages_cents: HISTORY_WINDOWS.to_h { |months| [ months.to_s, average_recurring_outside_income(months) ] },
        historical_category_spending_cents: historical_category_spending,
        recurring_obligations_cents: obligations,
        proposed_categories: category_rows,
        proposed_expense_total_cents: proposed_expenses,
        buffer_cents: buffer,
        buffer_basis_points: BUFFER_BASIS_POINTS,
        proposed_savings_cents: savings,
        planned_savings_allocations: planned_savings_allocations(savings),
        sinking_funds: { supported: false, reason: "No sinking-fund model exists" },
        excluded_category_spending_cents: excluded_category_spending,
        unresolved_transactions: unresolved_transactions,
        exclusions: {
          transfer_kinds: TransactionClassification::TRANSFER_KINDS,
          recurring_income_excludes: %w[windfall reimbursement refund]
        }
      }
    end

    def recurring_income_cents
      IncomeEstimate.includes(:income_source)
        .where(active: [ true, nil ])
        .select { |estimate| estimate.income_source.active != false }
        .sum do |estimate|
          Schedule.dates(estimate, from: @month, to: @month.end_of_month).length * estimate.estimated_amount_cents
        end
    end

    def recurring_obligations
      totals = Hash.new(0)
      RecurringExpense.where(active: [ true, nil ]).find_each do |expense|
        count = Schedule.dates(expense, from: @month, to: @month.end_of_month).length
        totals[expense.category_id] += count * expense.estimated_amount_cents
      end
      totals.sort.to_h.transform_keys(&:to_s)
    end

    def total_outside_income_for(month)
      external_transactions
        .joins(:category)
        .where(occurred_on: month..month.end_of_month, categories: { kind: "income" })
        .where("transactions.amount_cents > 0")
        .sum(:amount_cents)
    end

    def average_outside_income(months)
      months_range(months).sum { |month| total_outside_income_for(month) } / months
    end

    def average_recurring_outside_income(months)
      months_range(months).sum { |month| recurring_outside_income_for(month) } / months
    end

    def recurring_outside_income_monthly_totals(months)
      months_range(months).to_h do |month|
        [ month.iso8601, recurring_outside_income_for(month) ]
      end
    end

    def recurring_outside_income_for(month)
      excluded = TransactionClassification.where(kind: %w[windfall reimbursement refund]).select(:transaction_id)
      external_transactions.where.not(id: excluded)
        .joins(:category)
        .where(occurred_on: month..month.end_of_month, categories: { kind: "income" })
        .where("transactions.amount_cents > 0")
        .sum(:amount_cents)
    end

    def historical_category_spending
      HISTORY_WINDOWS.to_h do |months|
        start_on = @month.prev_month(months)
        end_on = @month - 1.day
        sums = budget_transactions.joins(:category)
          .where(occurred_on: start_on..end_on, categories: { kind: "expense" })
          .group(:category_id)
          .sum(:amount_cents)
        averages = sums.to_h { |category_id, signed_cents| [ category_id.to_s, [ (-signed_cents.to_f / months).round, 0 ].max ] }
        [ months.to_s, averages.sort.to_h ]
      end
    end

    def proposed_categories(obligations)
      previous_items = BudgetMonth.find_by(month: @month.prev_month)&.budget_items&.index_by(&:category_id) || {}
      spending = historical_category_spending
      budget_categories.order(:id).filter_map do |category|
        history_values = HISTORY_WINDOWS.to_h { |months| [ months.to_s, spending.fetch(months.to_s, {}).fetch(category.id.to_s, 0) ] }
        recurring = obligations.fetch(category.id.to_s, 0)
        previous = previous_items[category.id]&.assigned_cents.to_i
        proposed = [ previous, history_values.fetch("3"), recurring ].max
        next if proposed.zero?

        {
          category_id: category.id,
          category_name: category.name,
          category_group: category.group,
          previous_budget_cents: previous,
          average_spending_cents: history_values,
          recurring_obligation_cents: recurring,
          proposed_cents: proposed,
          rationale: "max(previous_budget, three_month_average, recurring_obligation)"
        }
      end
    end

    def planned_savings_allocations(savings_cents)
      return [] unless savings_cents.positive?

      [ { name: "Planned savings", proposed_cents: savings_cents } ]
    end

    def excluded_category_spending
      start_on = @month.prev_month(HISTORY_WINDOWS.max)
      end_on = @month - 1.day

      NON_BUDGET_CATEGORY_NAMES.to_h do |name|
        signed_cents = external_transactions.joins(:category)
          .where(occurred_on: start_on..end_on, categories: { name: })
          .sum(:amount_cents)
        [ name, [ -signed_cents, 0 ].max ]
      end
    end

    def unresolved_transactions
      start_on = @month.prev_month(HISTORY_WINDOWS.max)
      end_on = @month - 1.day
      entries = StatementEntry.where(status: "parsed", resolution_status: %w[unresolved ambiguous])
        .where("COALESCE(transaction_on, posted_on) BETWEEN ? AND ?", start_on, end_on)

      {
        count: entries.count,
        amount_cents: entries.sum("ABS(amount_cents)")
      }
    end

    def months_range(months)
      months.downto(1).map { |offset| @month.prev_month(offset) }
    end

    def external_transactions
      Transaction.excluding_transfers
    end

    def budget_transactions
      external_transactions.joins(:category)
        .where.not(categories: { name: NON_BUDGET_CATEGORY_NAMES })
    end

    def budget_categories
      Category.where(kind: "expense", archived: [ false, nil ])
        .where.not(name: NON_BUDGET_CATEGORY_NAMES)
    end

    def canonical(value)
      case value
      when Hash
        value.keys.sort_by(&:to_s).to_h { |key| [ key.to_s, canonical(value.fetch(key)) ] }
      when Array
        value.map { |item| canonical(item) }
      else
        value
      end
    end
  end
end
