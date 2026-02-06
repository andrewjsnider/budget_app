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

    spent_by_category_id = Transaction
      .where(category_id: category_ids)
      .where(occurred_on: date_range)
      .group(:category_id)
      .sum(:amount_cents)

    @expense_categories.map do |cat|
      assigned = @assigned_by_category_id[cat.id].to_i
      spent = spent_by_category_id[cat.id].to_i

      activity = -spent

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
