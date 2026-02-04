class AccountsController < ApplicationController
  def index
    @accounts = Account.where(archived: [false, nil]).order(:name)
  end

  def show
    @account = Account.find(params[:id])

    @month = parse_month(params[:month]) || Date.current.beginning_of_month

    @transactions = @account.transactions
      .where(occurred_on: @month..@month.end_of_month)
      .order(occurred_on: :desc, id: :desc)
  end

  private

  def parse_month(value)
    return nil if value.blank?
    Date.strptime(value, "%Y-%m").beginning_of_month
  rescue ArgumentError
    nil
  end
end
