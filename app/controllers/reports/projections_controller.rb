module Reports
  class ProjectionsController < ApplicationController
    def show
      @account = Account.find(params[:account_id])
      @from = parse_date(params[:from]) || Date.current
      @to = parse_date(params[:to]) || (Date.current + 30.days)

      @projection = AccountProjection.new(account: @account, from: @from, to: @to)
      @daily = @projection.daily_balances
      @ending_balance_cents = @daily[@to]
    end

    private

    def parse_date(value)
      return nil if value.blank?
      Date.parse(value)
    rescue ArgumentError
      nil
    end
  end
end
