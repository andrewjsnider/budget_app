module Reports
  class UtilitiesController < ApplicationController
    def index
      @from = parse_month(params[:from]) || (Date.current.beginning_of_month - 11.months)
      @to = parse_month(params[:to]) || Date.current.beginning_of_month
      @report = UtilitiesReport.new(from: @from, to: @to)
    end

    private

    def parse_month(value)
      return nil if value.blank?
      Date.strptime(value, "%Y-%m").beginning_of_month
    rescue ArgumentError
      nil
    end
  end
end
