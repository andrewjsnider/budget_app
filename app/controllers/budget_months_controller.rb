class BudgetMonthsController < ApplicationController
  def index
    month = parse_month(params[:month]) || Date.current.beginning_of_month
    redirect_to budget_month_path(month: month.strftime("%Y-%m"))
  end

  def show
    @month = parse_month(params[:month]) || Date.current.beginning_of_month
    @budget_month = BudgetMonth.find_or_create_by!(month: @month)

    @expense_categories = Category.where(kind: "expense", archived: [false, nil]).order(:group, :name)
    @income_cents = Transaction.joins(:category)
      .where(occurred_on: @month..@month.end_of_month)
      .where(categories: { kind: "income" })
      .sum(:amount_cents)

    items = @budget_month.budget_items.includes(:category).index_by(&:category_id)
    @assigned_by_category_id = items.transform_values(&:assigned_cents)

    @assigned_total_cents = @budget_month.budget_items.sum(:assigned_cents)
    @to_assign_cents = @income_cents - @assigned_total_cents

    @rows = BudgetMonthCategoryRows.new(
      month: @month,
      expense_categories: @expense_categories,
      assigned_by_category_id: @assigned_by_category_id
    ).rows
  end

  def update
    @month = parse_month(params[:month]) || Date.current.beginning_of_month
    @budget_month = BudgetMonth.find_or_create_by!(month: @month)

    permitted = params.fetch(:assigned, {}).permit!

    permitted.each do |category_id, raw|
      cents = parse_cents(raw)
      next if cents.nil?

      item = @budget_month.budget_items.find_or_initialize_by(category_id: category_id)
      item.assigned_cents = cents
      item.save!
    end

    redirect_to budget_month_path(month: @month.strftime("%Y-%m")), notice: "Updated."
  end

  private

  def parse_month(value)
    return nil if value.blank?
    Date.strptime(value, "%Y-%m").beginning_of_month
  rescue ArgumentError
    nil
  end

  def parse_cents(raw)
    return 0 if raw == "0"
    return nil if raw.blank?

    str = raw.to_s.strip
    if str.include?(".")
      dollars = (str.to_f * 100.0).round
      dollars
    else
      (str.to_i * 100)
    end
  end
end
