class BudgetMonthCategoryRows
  SORT_KEYS = %w[category group assigned activity available].freeze
  DEFAULT_DIRECTIONS = {
    "category" => "asc",
    "group" => "asc",
    "assigned" => "desc",
    "activity" => "desc",
    "available" => "desc"
  }.freeze
  DIRECTIONS = %w[asc desc].freeze

  Row = Struct.new(
    :category,
    :assigned_cents,
    :activity_cents,
    :available_cents,
    keyword_init: true
  )

  attr_reader :sort_key, :direction

  def initialize(month:, expense_categories:, assigned_by_category_id:, sort: nil, direction: nil)
    @month = month
    @expense_categories = expense_categories
    @assigned_by_category_id = assigned_by_category_id
    @sort_key = sort.to_s.presence_in(SORT_KEYS)
    @direction = normalized_direction(direction)
  end

  def rows
    category_ids = @expense_categories.map(&:id)

    spent_by_category_id = Transaction.excluding_transfers
      .where(category_id: category_ids)
      .where(occurred_on: date_range)
      .group(:category_id)
      .sum(:amount_cents)

    rows = @expense_categories.map do |cat|
      assigned = @assigned_by_category_id[cat.id].to_i
      net_activity = spent_by_category_id[cat.id].to_i
      spent = -net_activity

      Row.new(
        category: cat,
        assigned_cents: assigned,
        activity_cents: spent,
        available_cents: assigned - spent
      )
    end

    sort_rows(rows)
  end

  private

  def date_range
    @month..@month.end_of_month
  end

  def normalized_direction(raw_direction)
    return unless sort_key

    raw_direction.to_s.presence_in(DIRECTIONS) || DEFAULT_DIRECTIONS.fetch(sort_key)
  end

  def sort_rows(rows)
    return rows unless sort_key

    sorted = rows.sort_by { |row| [ sort_value(row), row.category.name.to_s.downcase, row.category.id ] }
    direction == "desc" ? sorted.reverse : sorted
  end

  def sort_value(row)
    case sort_key
    when "category" then row.category.name.to_s.downcase
    when "group" then row.category.group.to_s.downcase
    when "assigned" then row.assigned_cents
    when "activity" then row.activity_cents
    when "available" then row.available_cents
    end
  end
end
