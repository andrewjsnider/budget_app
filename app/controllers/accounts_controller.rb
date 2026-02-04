class AccountsController < ApplicationController
  def index
    @accounts = Account.where(archived: [false, nil]).order(:name)
  end

  def show
    @account = Account.find(params[:id])
    @month = parse_month(params[:month]) || Date.current.beginning_of_month

    @transactions = @account.transactions
      .includes(:category)
      .where(occurred_on: @month..@month.end_of_month)
      .order(occurred_on: :desc, id: :desc)
  end

  def new
    @account = Account.new
  end

  def create
    @account = Account.new(account_params)

    if @account.save
      redirect_to accounts_path, notice: "Created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @account = Account.find(params[:id])
  end

  def update
    @account = Account.find(params[:id])

    if @account.update(account_params)
      redirect_to account_path(@account), notice: "Updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:account).permit(:name, :kind, :archived)
  end

  def parse_month(value)
    return nil if value.blank?
    Date.strptime(value, "%Y-%m").beginning_of_month
  rescue ArgumentError
    nil
  end
end
