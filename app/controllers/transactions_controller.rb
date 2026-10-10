class TransactionsController < ApplicationController
  include ActionView::RecordIdentifier

  FILTER_KEYS = %i[
    q account_id category_id start_date end_date flow reconciliation_status cleared_status
  ].freeze
  SEARCH_PARAM_KEYS = (FILTER_KEYS + %i[sort direction]).freeze

  def index
    @month = parse_month(params[:month]) || Date.current.beginning_of_month
    @accounts = Account.where(archived: [ false, nil ]).order(:name)
    @account = params[:account_id].present? ? @accounts.find { |a| a.id == params[:account_id].to_i } : nil

    @category = params[:category_id].present? ? Category.find_by(id: params[:category_id]) : nil
    @categories = Category.order(:group, :name)
    @filter_values = search_params

    search = TransactionSearch.new(
      scope: Transaction.all,
      params: @filter_values,
      default_date_range: @month..@month.end_of_month
    )
    @transactions = search.call.includes(:category, :account)
    @transaction_sort = search.sort_key
    @transaction_direction = search.direction
    @filters_active = FILTER_KEYS.any? { |key| @filter_values[key].present? }
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
            helpers.dom_id(@transaction),
            partial: "transactions/row",
            locals: { t: @transaction, categories: @categories, flash_updated: true }
          )
        end

        format.html do
          redirect_to transactions_path(month: params[:month], account_id: params[:account_id]),
                      notice: "Updated."
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(@transaction),
            partial: "transactions/row",
            locals: { t: @transaction, categories: @categories, flash_updated: false }
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

  def search_params
    SEARCH_PARAM_KEYS.index_with { |key| params[key] }
  end

  def transaction_params
    params.require(:transaction).permit(:occurred_on, :description, :amount_cents, :category_id, :account_id)
  end

  def load_selects
    @accounts = Account.where(archived: [ false, nil ]).order(:name)
    @categories = Category.where(archived: [ false, nil ]).order(:kind, :group, :name)
  end

  def parse_month(value)
    return nil if value.blank?
    Date.strptime(value, "%Y-%m").beginning_of_month
  rescue ArgumentError
    nil
  end
end
