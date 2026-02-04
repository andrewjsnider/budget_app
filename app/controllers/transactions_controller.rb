class TransactionsController < ApplicationController
  def index
    @month = parse_month(params[:month]) || Date.current.beginning_of_month
    @accounts = Account.where(archived: [false, nil]).order(:name)
    @account = params[:account_id].present? ? @accounts.find { |a| a.id == params[:account_id].to_i } : nil

    scope = Transaction.includes(:category, :account).where(occurred_on: @month..@month.end_of_month).order(occurred_on: :desc, id: :desc)
    scope = scope.where(account_id: @account.id) if @account.present?
    @transactions = scope
  end

  def new
    @transaction = Transaction.new(occurred_on: Date.current, amount_cents: 0)
    load_selects
  end

  def create
    @transaction = Transaction.new(transaction_params)

    if @transaction.save
      redirect_to transactions_path(month: @transaction.occurred_on.beginning_of_month.strftime("%Y-%m")), notice: "Created."
    else
      load_selects
      flash.now[:alert] = @transaction.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @transaction = Transaction.find(params[:id])
    load_selects
  end

  def update
    @transaction = Transaction.find(params[:id])

    if @transaction.update(transaction_params)
      redirect_to transactions_path(month: @transaction.occurred_on.beginning_of_month.strftime("%Y-%m")), notice: "Updated."
    else
      load_selects
      flash.now[:alert] = @transaction.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def transaction_params
    params.require(:transaction).permit(:occurred_on, :description, :amount_cents, :account_id, :category_id)
  end

  def load_selects
    @accounts = Account.where(archived: [false, nil]).order(:name)
    @categories = Category.where(archived: [false, nil]).order(:kind, :group, :name)
  end

  def parse_month(value)
    return nil if value.blank?
    Date.strptime(value, "%Y-%m").beginning_of_month
  rescue ArgumentError
    nil
  end
end
