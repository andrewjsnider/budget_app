# app/services/budget_month_category_rows.rb
class BudgetMonthCategoryRows
  Row = Struct.new(
    :category,
    :assigned_cents,
    :activity_cents,
    :available_cents,
    keyword_init: true
  )

  def initialize(month:, expense_categories:, assigned_by_category_id:)
    @month = month
    @expense_categories = expense_categories
    @assigned_by_category_id = assigned_by_category_id
  end

  def rows
    category_ids = @expense_categories.map(&:id)

    activity_by_category_id = Transaction
      .where(category_id: category_ids)
      .where(occurred_on: date_range)
      .where("amount_cents < 0")
      .group(:category_id)
      .sum(:amount_cents)

    @expense_categories.map do |cat|
      assigned = @assigned_by_category_id[cat.id].to_i
      activity = activity_by_category_id[cat.id].to_i
      Row.new(
        category: cat,
        assigned_cents: assigned,
        activity_cents: activity,
        available_cents: assigned + activity
      )
    end
  end

  private

  def date_range
    @month..@month.end_of_month
  end
end
