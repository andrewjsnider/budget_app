module Reports
  class UtilitiesController < ApplicationController
    def index
      @from = parse_month(params[:from]) || (Date.current.beginning_of_month - 11.months)
      @to = parse_month(params[:to]) || Date.current.beginning_of_month

      @months = month_series(@from, @to)

      @utility_categories = Category.utility_expenses.order(:name)

      signed_totals = Transaction
        .excluding_transfers
        .joins(:category)
        .where(categories: { id: @utility_categories.select(:id) })
        .where(occurred_on: @from..@to.end_of_month)
        .group("date_trunc('month', occurred_on)", "categories.id")
        .sum(:amount_cents)

      @spending_by_month_and_category = signed_totals.each_with_object({}) do |((month_ts, category_id), signed_cents), spending|
        spending[[ month_ts.to_date.beginning_of_month, category_id ]] = -signed_cents
      end
    end

    private

    def parse_month(value)
      return nil if value.blank?
      Date.strptime(value, "%Y-%m").beginning_of_month
    rescue ArgumentError
      nil
    end

    def month_series(from, to)
      m = from.beginning_of_month
      out = []
      while m <= to.beginning_of_month
        out << m
        m = m.next_month
      end
      out
    end
  end
end
