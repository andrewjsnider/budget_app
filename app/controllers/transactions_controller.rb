class TransactionsController < ApplicationController
  include ActionView::RecordIdentifier

  def index
    @month = parse_month(params[:month]) || Date.current.beginning_of_month
    @accounts = Account.where(archived: [false, nil]).order(:name)
    @account = params[:account_id].present? ? @accounts.find { |a| a.id == params[:account_id].to_i } : nil

    @category = params[:category_id].present? ? Category.find_by(id: params[:category_id]) : nil
    @categories = Category.order(:group, :name)

    scope = Transaction
      .includes(:category, :account)
      .where(occurred_on: @month..@month.end_of_month)
      .order(occurred_on: :desc, id: :desc)

    scope = scope.where(account_id: @account.id) if @account.present?
    scope = scope.where(category_id: @category.id) if @category.present?

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
    @categories = Category.order(:group, :name)

    if @transaction.update(transaction_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(@transaction),
            partial: "transactions/row",
            locals: { t: @transaction, categories: @categories }
          )
        end
        format.html { redirect_to transactions_path(month: params[:month], account_id: params[:account_id]), notice: "Updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(@transaction),
            partial: "transactions/row",
            locals: { t: @transaction, categories: @categories }
          ), status: :unprocessable_entity
        end
        format.html do
          redirect_to transactions_path(month: params[:month], account_id: params[:account_id]),
                      alert: @transaction.errors.full_messages.to_sentence
        end
      end
    end
  end


  private

  def transaction_params
    params.require(:transaction).permit(:occurred_on, :description, :amount_cents, :category_id, :account_id)
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
