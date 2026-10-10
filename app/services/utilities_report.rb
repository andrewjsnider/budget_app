class UtilitiesReport
  CategoryTrend = Data.define(
    :category,
    :latest_cents,
    :previous_cents,
    :average_cents,
    :change_cents,
    :change_percentage,
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

      CategoryTrend.new(
        category:,
        latest_cents:,
        previous_cents:,
        average_cents: months.empty? ? 0 : (monthly_cents.values.sum.fdiv(months.length)).round,
        change_cents:,
        change_percentage: percentage_change(change_cents, previous_cents),
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

  def trend_chart(trend)
    chart_data(trend.monthly_cents)
  end

  private

  def spending_by_month_and_category
    @spending_by_month_and_category ||= signed_totals.each_with_object({}) do |((month, category_id), signed_cents), spending|
      spending[[ month.to_date.beginning_of_month, category_id ]] = -signed_cents
    end
  end

  def signed_totals
    @transaction_scope
      .joins(:category)
      .where(categories: { id: categories.map(&:id) })
      .where(occurred_on: from..to.end_of_month)
      .group("date_trunc('month', transactions.occurred_on)", "categories.id")
      .sum(:amount_cents)
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

  def chart_data(cents_by_month)
    cents_by_month.to_h { |month, cents| [ month.strftime("%b %Y"), dollars(cents) ] }
  end

  def dollars(cents)
    cents / 100.0
  end
end
