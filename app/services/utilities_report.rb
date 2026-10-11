class UtilitiesReport
  CategoryTrend = Data.define(
    :category,
    :latest_cents,
    :previous_cents,
    :average_cents,
    :change_cents,
    :change_percentage,
    :current_period_cents,
    :previous_period_cents,
    :year_over_year_change_cents,
    :year_over_year_change_percentage,
    :monthly_cents
  ) do
    def new_this_month?
      previous_cents == 0 && latest_cents != 0
    end
  end

  attr_reader :from, :to, :months, :categories

  def initialize(from:, to:, transaction_scope: Transaction.excluding_transfers, category_scope: Category.utility_expenses)
    @from = from.beginning_of_month
    @to = to.beginning_of_month
    @transaction_scope = transaction_scope
    @categories = category_scope.order(:name).to_a
    @months = month_series
  end

  def spending_cents(month, category)
    spending_by_month_and_category.fetch([ month.beginning_of_month, category.id ], 0)
  end

  def monthly_totals_cents
    @monthly_totals_cents ||= months.to_h do |month|
      [ month, categories.sum { |category| spending_cents(month, category) } ]
    end
  end

  def totals_by_category
    @totals_by_category ||= categories
      .map { |category| [ category, months.sum { |month| spending_cents(month, category) } ] }
      .sort_by { |category, cents| [ -cents, category.name ] }
  end

  def latest_month
    months.last
  end

  def latest_month_cents
    latest_month ? monthly_totals_cents.fetch(latest_month) : 0
  end

  def average_monthly_cents
    return 0 if months.empty?

    (monthly_totals_cents.values.sum.fdiv(months.length)).round
  end

  def current_period_cents
    monthly_totals_cents.values.sum
  end

  def previous_period_cents
    previous_months.sum { |month| previous_month_total_cents(month) }
  end

  def year_over_year_change_cents
    current_period_cents - previous_period_cents
  end

  def year_over_year_change_percentage
    percentage_change(year_over_year_change_cents, previous_period_cents)
  end

  def comparison_from
    from.prev_year
  end

  def comparison_to
    to.prev_year
  end

  def period_label
    return "Year total" if full_calendar_year?
    return "Year to date" if partial_calendar_year?

    "Selected period"
  end

  def yearly_totals_cents
    @yearly_totals_cents ||= months.group_by(&:year).transform_values do |year_months|
      year_months.sum { |month| monthly_totals_cents.fetch(month) }
    end
  end

  def highest_month
    monthly_totals_cents.max_by { |_month, cents| cents }
  end

  def highest_category
    totals_by_category.first
  end

  def category_trends
    @category_trends ||= categories.map do |category|
      monthly_cents = months.to_h { |month| [ month, spending_cents(month, category) ] }
      latest_cents = latest_month ? monthly_cents.fetch(latest_month) : 0
      previous_cents = months.length > 1 ? monthly_cents.fetch(months[-2]) : nil
      change_cents = previous_cents.nil? ? nil : latest_cents - previous_cents
      current_period_cents = monthly_cents.values.sum
      previous_period_cents = previous_months.sum { |month| previous_spending_cents(month, category) }
      year_over_year_change_cents = current_period_cents - previous_period_cents

      CategoryTrend.new(
        category:,
        latest_cents:,
        previous_cents:,
        average_cents: months.empty? ? 0 : (monthly_cents.values.sum.fdiv(months.length)).round,
        change_cents:,
        change_percentage: percentage_change(change_cents, previous_cents),
        current_period_cents:,
        previous_period_cents:,
        year_over_year_change_cents:,
        year_over_year_change_percentage: percentage_change(year_over_year_change_cents, previous_period_cents),
        monthly_cents:
      )
    end
  end

  def monthly_totals_chart
    chart_data(monthly_totals_cents)
  end

  def monthly_by_category_chart
    categories.map do |category|
      {
        name: category.name,
        data: chart_data(months.to_h { |month| [ month, spending_cents(month, category) ] })
      }
    end
  end

  def totals_by_category_chart
    totals_by_category.to_h { |category, cents| [ category.name, dollars(cents) ] }
  end

  def year_over_year_chart
    [
      {
        name: "Current period",
        data: months.to_h do |month|
          [ comparison_axis_label(month), dollars(monthly_totals_cents.fetch(month)) ]
        end
      },
      {
        name: "Same period last year",
        data: months.to_h do |month|
          [ comparison_axis_label(month), dollars(previous_month_total_cents(month.prev_year)) ]
        end
      }
    ]
  end

  def trend_chart(trend)
    chart_data(trend.monthly_cents)
  end

  private

  def spending_by_month_and_category
    @spending_by_month_and_category ||= aggregated_spending(from:, to:)
  end

  def previous_spending_by_month_and_category
    @previous_spending_by_month_and_category ||= aggregated_spending(from: comparison_from, to: comparison_to)
  end

  def aggregated_spending(from:, to:)
    @transaction_scope
      .joins(:category)
      .where(categories: { id: categories.map(&:id) })
      .where(occurred_on: from..to.end_of_month)
      .group("date_trunc('month', transactions.occurred_on)", "categories.id")
      .sum(:amount_cents)
      .each_with_object({}) do |((month, category_id), signed_cents), spending|
        spending[[ month.to_date.beginning_of_month, category_id ]] = -signed_cents
      end
  end

  def previous_months
    @previous_months ||= months.map(&:prev_year)
  end

  def previous_spending_cents(month, category)
    previous_spending_by_month_and_category.fetch([ month.beginning_of_month, category.id ], 0)
  end

  def previous_month_total_cents(month)
    categories.sum { |category| previous_spending_cents(month, category) }
  end

  def month_series
    return [] if to < from

    month = from
    series = []
    while month <= to
      series << month
      month = month.next_month
    end
    series
  end

  def percentage_change(change_cents, previous_cents)
    return nil if change_cents.nil? || previous_cents.zero?

    change_cents.fdiv(previous_cents.abs) * 100
  end

  def full_calendar_year?
    from.year == to.year && from.month == 1 && to.month == 12
  end

  def partial_calendar_year?
    from.year == to.year && from.month == 1 && to.month < 12
  end

  def comparison_axis_label(month)
    if months.map(&:month).uniq.length == months.length
      month.strftime("%b")
    else
      month.strftime("%b %Y")
    end
  end

  def chart_data(cents_by_month)
    cents_by_month.to_h { |month, cents| [ month.strftime("%b %Y"), dollars(cents) ] }
  end

  def dollars(cents)
    cents / 100.0
  end
end
