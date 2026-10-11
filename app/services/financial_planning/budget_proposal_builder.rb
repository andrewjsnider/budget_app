require "digest"
require "json"
require "set"

module FinancialPlanning
  class BudgetProposalBuilder
    BUFFER_BASIS_POINTS = 500
    PAYCHECK_HISTORY_MONTHS = 6
    SEASONAL_UTILITY_UPLIFT_BASIS_POINTS = 1_500
    HISTORY_WINDOWS = [ 3, 6, 12 ].freeze
    NON_BUDGET_CATEGORY_NAMES = [ "Uncategorized", "Credit Card Payments" ].freeze
    PAYCHECK_INCOME_SOURCE_KINDS = %w[w2 w-2].freeze
    LEGACY_IMPORTED_INCOME_CATEGORY_NAME = "Imported Income"
    PAYROLL_DESCRIPTION_PATTERN = /\b(payroll|salary|direct dep(?:osit)?)\b/i
    PAYROLL_DESCRIPTOR_SEPARATOR_PATTERN = /\s+(?:payroll|ach|ppd\s+id\b|direct dep(?:osit)?\b).*/i
    POTENTIALLY_FIXED_CATEGORY_GROUPS = %w[insurance subscription subscriptions].freeze
    POTENTIALLY_FIXED_CATEGORY_NAME_PATTERN = /\b(internet|mortgage|hoa dues?|phone)\b/i

    def self.call(month:, dry_run:, source: "paperclip", supersede: false)
      new(month:, dry_run:, source:, supersede:).call
    end

    def initialize(month:, dry_run:, source:, supersede:)
      @month = month.beginning_of_month
      @dry_run = dry_run
      @source = source
      @supersede = supersede
    end

    def call
      payload = build_payload
      digest = Digest::SHA256.hexdigest(JSON.generate(canonical(payload)))
      proposal = BudgetProposal.find_by(month: @month, input_digest: digest)
      superseded_proposal_ids = []
      unless @dry_run
        BudgetProposal.transaction do
          proposal ||= BudgetProposal.create!(
            month: @month,
            status: "draft",
            policy_version: BudgetProposal::POLICY_VERSION,
            input_digest: digest,
            source: @source,
            proposal: payload
          )
          if @supersede
            superseded = BudgetProposal.where(month: @month, status: "draft").where.not(id: proposal.id)
            superseded_proposal_ids = superseded.pluck(:id)
            superseded.find_each(&:destroy!)
          end
        end
      end
      validation_target = proposal || BudgetProposal.new(month: @month, proposal: canonical(payload))
      validation = BudgetProposals::Validation.call(validation_target)

      {
        policy_version: BudgetProposal::POLICY_VERSION,
        status: "draft",
        dry_run: @dry_run,
        persisted: proposal.present?,
        proposal_id: proposal&.id,
        superseded_proposal_ids: superseded_proposal_ids,
        review_status: validation.valid? ? "ready" : "invalid",
        validation_errors: validation.errors,
        validation_warnings: validation.warnings,
        input_digest: digest,
        proposal: payload
      }
    end

    private

    def build_payload
      monthly_paycheck_totals = paycheck_income_monthly_totals(PAYCHECK_HISTORY_MONTHS)
      available_income = arithmetic_mean(monthly_paycheck_totals.values)
      obligation_details = recurring_obligation_details
      obligations = recurring_obligations(obligation_details)
      spending = historical_category_spending
      category_rows = proposed_categories(obligations, obligation_details, spending)
      detection_gaps = recurring_detection_gaps(obligations, spending)
      proposed_expenses = category_rows.sum { |row| row.fetch(:proposed_cents) }
      buffer = (available_income * BUFFER_BASIS_POINTS / 10_000.0).round
      savings = [ available_income - proposed_expenses - buffer, 0 ].max

      {
        month: @month.iso8601,
        planning_baseline: "six_month_paycheck_average",
        available_paycheck_income_cents: available_income,
        paycheck_income_monthly_totals_cents: monthly_paycheck_totals,
        paycheck_income_six_month_average_cents: available_income,
        total_outside_income_previous_month_cents: total_outside_income_for(@month.prev_month),
        historical_category_spending_cents: spending,
        recurring_obligations_cents: obligations,
        recurring_obligation_details: obligation_details,
        subscriptions: obligation_details.select { |row| row.fetch(:expense_type) == "subscription" },
        recurring_detection_gaps: detection_gaps,
        validation_warnings: detection_gaps.map { |gap| gap.fetch(:warning) },
        merchant_concentration: merchant_concentration,
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

    def arithmetic_mean(values)
      return 0 if values.empty?

      values.sum.fdiv(values.length).round
    end

    def paycheck_income_monthly_totals(months)
      months_range(months).to_h do |month|
        [ month.iso8601, paycheck_income_for(month) ]
      end
    end

    def paycheck_income_for(month)
      direct_paychecks = paycheck_income_source_pairs.sum do |account_id, category_id|
        paycheck_transactions
          .where(account_id:, category_id:, occurred_on: month..month.end_of_month)
          .sum(:amount_cents)
      end
      direct_paychecks + legacy_paycheck_income_for(month)
    end

    def paycheck_income_source_pairs
      @paycheck_income_source_pairs ||= paycheck_income_sources
        .distinct
        .pluck(:account_id, :category_id)
    end

    def paycheck_income_sources
      IncomeSource.where(active: [ true, nil ])
        .where("LOWER(income_sources.kind) IN (?)", PAYCHECK_INCOME_SOURCE_KINDS)
    end

    def paycheck_transactions
      excluded = TransactionClassification.where(kind: %w[windfall reimbursement refund]).select(:transaction_id)
      external_transactions.where.not(id: excluded).where("transactions.amount_cents > 0")
    end

    def legacy_paycheck_income_for(month)
      return 0 if legacy_payroll_descriptors.empty?

      legacy_income_transactions
        .where(occurred_on: month..month.end_of_month)
        .sum do |transaction|
          legacy_payroll_descriptors.include?(payroll_descriptor(transaction.description)) ? transaction.amount_cents : 0
        end
    end

    def legacy_payroll_descriptors
      @legacy_payroll_descriptors ||= legacy_income_transactions.filter_map do |transaction|
        payroll_descriptor(transaction.description) if transaction.description.to_s.match?(PAYROLL_DESCRIPTION_PATTERN)
      end.to_set
    end

    def legacy_income_transactions
      paycheck_transactions.joins(:category)
        .where(account_id: paycheck_income_sources.select(:account_id))
        .where(categories: { name: LEGACY_IMPORTED_INCOME_CATEGORY_NAME })
    end

    def payroll_descriptor(description)
      description.to_s.upcase.sub(PAYROLL_DESCRIPTOR_SEPARATOR_PATTERN, "").strip
    end

    def recurring_obligations(details)
      totals = Hash.new(0)
      details.each do |row|
        totals[row.fetch(:category_id)] += row.fetch(:projected_monthly_cents)
      end
      totals.sort.to_h.transform_keys(&:to_s)
    end

    def recurring_obligation_details
      RecurringExpense.includes(:category).where(active: [ true, nil ]).order(:id).filter_map do |expense|
        occurrence_count = Schedule.dates(expense, from: @month, to: @month.end_of_month).length
        next if occurrence_count.zero?

        {
          recurring_expense_id: expense.id,
          name: expense.name,
          category_id: expense.category_id,
          category_name: expense.category.name,
          expense_type: expense.expense_type,
          cadence: expense.cadence,
          interval: expense.interval,
          occurrence_count: occurrence_count,
          amount_per_occurrence_cents: expense.estimated_amount_cents,
          projected_monthly_cents: occurrence_count * expense.estimated_amount_cents,
          amount_source: "RecurringExpense ##{expense.id}",
          amount_source_type: "recurring_expense"
        }
      end
    end

    def total_outside_income_for(month)
      external_transactions
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

    def proposed_categories(obligations, obligation_details, spending)
      previous_items = BudgetMonth.find_by(month: @month.prev_month)&.budget_items&.index_by(&:category_id) || {}
      prior_spending = prior_three_month_category_spending
      same_month_last_year = same_month_last_year_category_spending
      details_by_category = obligation_details.group_by { |row| row.fetch(:category_id).to_s }
      budget_categories.order(:id).filter_map do |category|
        history_values = HISTORY_WINDOWS.to_h { |months| [ months.to_s, spending.fetch(months.to_s, {}).fetch(category.id.to_s, 0) ] }
        current_three_month_average = history_values.fetch("3")
        prior_three_month_average = prior_spending.fetch(category.id.to_s, 0)
        recurring = obligations.fetch(category.id.to_s, 0)
        previous = previous_items[category.id]&.assigned_cents.to_i
        prior_year = same_month_last_year.fetch(category.id.to_s, 0)
        proposed, calculation_basis, calculation_basis_label = category_calculation(
          category:,
          recurring:,
          prior_year:,
          six_month_average: history_values.fetch("6")
        )
        next if proposed.zero?

        {
          category_id: category.id,
          category_name: category.name,
          category_group: category.group,
          previous_budget_cents: previous,
          average_spending_cents: history_values,
          trend_data: {
            current_three_month_average_cents: current_three_month_average,
            prior_three_month_average_cents: prior_three_month_average,
            change_cents: current_three_month_average - prior_three_month_average,
            change_percentage: percentage_change(current_three_month_average, prior_three_month_average)
          },
          recurring_obligation_cents: recurring,
          recurring_expense_ids: details_by_category.fetch(category.id.to_s, []).map { |detail| detail.fetch(:recurring_expense_id) },
          same_month_last_year_cents: prior_year,
          seasonal_utility_uplift_basis_points: seasonal_utility?(category) ? SEASONAL_UTILITY_UPLIFT_BASIS_POINTS : nil,
          proposed_cents: proposed,
          calculation_basis: calculation_basis,
          calculation_basis_label: calculation_basis_label,
          rationale: calculation_basis
        }
      end
    end

    def category_calculation(category:, recurring:, prior_year:, six_month_average:)
      if recurring.positive?
        [ recurring, "known_recurring_amount", "Known recurring amount" ]
      elsif seasonal_utility?(category) && prior_year.positive?
        proposed = (prior_year * (10_000 + SEASONAL_UTILITY_UPLIFT_BASIS_POINTS) / 10_000.0).round
        [ proposed, "same_month_last_year_plus_15_percent", "Same month last year + 15%" ]
      else
        [ six_month_average, "six_month_spending_average", "6-month spending average" ]
      end
    end

    def same_month_last_year_category_spending
      month = @month.prev_year
      sums = budget_transactions.joins(:category)
        .where(occurred_on: month..month.end_of_month, categories: { kind: "expense" })
        .group(:category_id)
        .sum(:amount_cents)

      sums.to_h do |category_id, signed_cents|
        [ category_id.to_s, [ -signed_cents, 0 ].max ]
      end.sort.to_h
    end

    def seasonal_utility?(category)
      category.group.to_s.casecmp(Category::UTILITY_GROUP).zero? && !potentially_fixed_recurring?(category)
    end

    def recurring_detection_gaps(obligations, spending)
      six_month_spending = spending.fetch("6")

      budget_categories.order(:id).filter_map do |category|
        next if obligations.fetch(category.id.to_s, 0).positive?
        next unless six_month_spending.fetch(category.id.to_s, 0).positive?
        next unless potentially_fixed_recurring?(category)

        {
          category_id: category.id,
          category_name: category.name,
          fallback_basis: "six_month_spending_average",
          warning: "#{category.name} may be a fixed recurring bill, but it has no active RecurringExpense; the proposal uses its six-month spending average."
        }
      end
    end

    def potentially_fixed_recurring?(category)
      POTENTIALLY_FIXED_CATEGORY_GROUPS.include?(category.group.to_s.downcase) ||
        category.name.to_s.match?(POTENTIALLY_FIXED_CATEGORY_NAME_PATTERN)
    end

    def prior_three_month_category_spending
      start_on = @month.prev_month(6)
      end_on = @month.prev_month(3) - 1.day
      sums = budget_transactions.joins(:category)
        .where(occurred_on: start_on..end_on, categories: { kind: "expense" })
        .group(:category_id)
        .sum(:amount_cents)

      sums.to_h do |category_id, signed_cents|
        [ category_id.to_s, [ (-signed_cents.to_f / 3).round, 0 ].max ]
      end.sort.to_h
    end

    def percentage_change(current, previous)
      return nil unless previous.positive?

      ((current - previous).fdiv(previous) * 100).round(1)
    end

    def merchant_concentration
      start_on = @month.prev_month(6)
      end_on = @month - 1.day
      scope = budget_transactions.joins(:category)
        .where(occurred_on: start_on..end_on, categories: { kind: "expense" })
      signed_totals = scope.group(:category_id, :description).sum(:amount_cents)
      transaction_counts = scope.group(:category_id, :description).count
      categories = Category.where(id: signed_totals.keys.map(&:first)).index_by(&:id)

      rows = signed_totals.filter_map do |(category_id, description), signed_cents|
        spending = [ -signed_cents, 0 ].max
        next if spending.zero?

        {
          category_id: category_id,
          category_name: categories.fetch(category_id).name,
          merchant: description.presence || "No description",
          six_month_spending_cents: spending,
          monthly_average_cents: (spending / 6.0).round,
          transaction_count: transaction_counts.fetch([ category_id, description ])
        }
      end

      category_totals = rows.group_by { |row| row.fetch(:category_id) }
        .transform_values { |category_rows| category_rows.sum { |row| row.fetch(:six_month_spending_cents) } }
      rows.each do |row|
        total = category_totals.fetch(row.fetch(:category_id))
        row[:category_share_percentage] = (row.fetch(:six_month_spending_cents).fdiv(total) * 100).round(1)
      end

      rows.group_by { |row| row.fetch(:category_id) }
        .values
        .flat_map { |category_rows| category_rows.sort_by { |row| -row.fetch(:six_month_spending_cents) }.first(5) }
        .sort_by { |row| [ row.fetch(:category_name), -row.fetch(:six_month_spending_cents) ] }
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
