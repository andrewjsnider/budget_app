require "test_helper"

class UtilitiesReportTest < ActiveSupport::TestCase
  setup do
    @account = create(:account)
    @electric = create(:category, name: "Electric", kind: "expense", group: "utilities", archived: false)
    @water = create(:category, name: "Water", kind: "expense", group: "utilities", archived: false)
    @groceries = create(:category, name: "Groceries", kind: "expense", group: "food", archived: false)

    create_transaction("2026-01-05", -10_000, @electric)
    create_transaction("2026-01-06", -5_000, @water)
    create_transaction("2026-02-05", -12_000, @electric)
    create_transaction("2026-02-10", 2_000, @electric)
    create_transaction("2026-03-05", -7_000, @water)
    create_transaction("2026-04-05", -20_000, @electric)
    create_transaction("2026-04-06", -10_000, @water)
    create_transaction("2026-01-07", -99_999, @groceries)
    create_transfer("2026-02-15", 50_000)
  end

  test "aggregates signed utility spending by month with zeros and exclusions" do
    report = build_report

    assert_equal %w[2026-01-01 2026-02-01 2026-03-01 2026-04-01], report.months.map(&:to_s)
    assert_equal 10_000, report.spending_cents(Date.new(2026, 2, 1), @electric), "refunds should reduce spend"
    assert_equal 0, report.spending_cents(Date.new(2026, 3, 1), @electric)
    assert_equal [ 15_000, 10_000, 7_000, 30_000 ], report.monthly_totals_cents.values
    assert_equal [ [ "Electric", 40_000 ], [ "Water", 22_000 ] ],
      report.totals_by_category.map { |category, cents| [ category.name, cents ] }

    assert_equal [ "Electric", "Water" ], report.monthly_by_category_chart.pluck(:name)
    assert_equal 0.0, report.monthly_by_category_chart.first[:data].fetch("Mar 2026")
  end

  test "calculates latest average highest month and largest category" do
    report = build_report

    assert_equal Date.new(2026, 4, 1), report.latest_month
    assert_equal 30_000, report.latest_month_cents
    assert_equal 15_500, report.average_monthly_cents
    assert_equal [ Date.new(2026, 4, 1), 30_000 ], report.highest_month
    assert_equal [ @electric, 40_000 ], report.highest_category
  end

  test "calculates utility trends and omits percentage when previous month is zero" do
    trends = build_report.category_trends.index_by { |trend| trend.category.name }
    electric = trends.fetch("Electric")
    water = trends.fetch("Water")

    assert_equal 20_000, electric.latest_cents
    assert_equal 0, electric.previous_cents
    assert_equal 10_000, electric.average_cents
    assert_equal 20_000, electric.change_cents
    assert_nil electric.change_percentage
    assert electric.new_this_month?

    assert_equal 10_000, water.latest_cents
    assert_equal 7_000, water.previous_cents
    assert_equal 5_500, water.average_cents
    assert_equal 3_000, water.change_cents
    assert_in_delta 42.857, water.change_percentage, 0.001
    refute water.new_this_month?
  end

  test "preserves negative net spending when credits exceed charges" do
    credit = create_transaction("2026-05-05", 2_500, @electric)
    report = UtilitiesReport.new(from: Date.new(2026, 5, 1), to: Date.new(2026, 5, 1))

    assert_predicate credit, :persisted?
    assert_equal(-2_500, report.latest_month_cents)
    assert_equal(-25.0, report.monthly_totals_chart.fetch("May 2026"))
  end

  private

  def build_report
    UtilitiesReport.new(from: Date.new(2026, 1, 1), to: Date.new(2026, 4, 1))
  end

  def create_transaction(date, amount_cents, category)
    create(:transaction, occurred_on: Date.parse(date), amount_cents:, category:, account: @account)
  end

  def create_transfer(date, amount_cents)
    savings = create(:account, kind: "savings")
    utility_leg = create_transaction(date, -amount_cents, @electric)
    other_leg = create(:transaction, occurred_on: Date.parse(date), amount_cents:, category: @groceries, account: savings)
    group_key = "transfer-#{utility_leg.id}-#{other_leg.id}"

    create(:transaction_classification, ledger_transaction: utility_leg, paired_transaction: other_leg, kind: "internal_transfer", group_key:)
    create(:transaction_classification, ledger_transaction: other_leg, paired_transaction: utility_leg, kind: "internal_transfer", group_key:)
  end
end
