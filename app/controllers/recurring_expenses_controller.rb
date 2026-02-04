class RecurringExpensesController < ApplicationController
  def index
    @recurring_expenses = RecurringExpense.includes(:account, :category).order(:name)
  end

  def new
    @recurring_expense = RecurringExpense.new(active: true, interval: 1, cadence: "monthly", start_on: Date.current.beginning_of_month, day_of_month: 1)
    load_selects
  end

  def create
    @recurring_expense = RecurringExpense.new(recurring_expense_params)
    if @recurring_expense.save
      redirect_to recurring_expenses_path, notice: "Created."
    else
      load_selects
      flash.now[:alert] = @recurring_expense.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @recurring_expense = RecurringExpense.find(params[:id])
    load_selects
  end

  def update
    @recurring_expense = RecurringExpense.find(params[:id])
    if @recurring_expense.update(recurring_expense_params)
      redirect_to recurring_expenses_path, notice: "Updated."
    else
      load_selects
      flash.now[:alert] = @recurring_expense.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def recurring_expense_params
    params.require(:recurring_expense).permit(
      :name, :active, :account_id, :category_id, :cadence, :interval,
      :weekday, :day_of_month, :estimated_amount_cents, :start_on, :end_on
    )
  end

  def load_selects
    @accounts = Account.where(archived: [false, nil]).order(:name)
    @categories = Category.where(kind: "expense", archived: [false, nil]).order(:group, :name)
    @cadences = %w[weekly biweekly monthly quarterly yearly]
  end
end
