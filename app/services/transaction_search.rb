class TransactionSearch
  SORT_KEYS = %w[date description account category amount].freeze

  DEFAULT_DIRECTIONS = {
    "date" => "desc",
    "description" => "asc",
    "account" => "asc",
    "category" => "asc",
    "amount" => "desc"
  }.freeze

  DIRECTIONS = %w[asc desc].freeze

  attr_reader :sort_key, :direction

  def initialize(scope:, params:, default_date_range:)
    @scope = scope
    @params = params
    @default_date_range = default_date_range
    @sort_key = value(:sort).presence_in(SORT_KEYS)
    @direction = normalized_direction
  end

  def call
    relation = apply_date_filter(@scope)
    relation = apply_search(relation)
    relation = apply_id_filter(relation, :account_id)
    relation = apply_id_filter(relation, :category_id)
    relation = apply_flow_filter(relation)
    relation = apply_reconciliation_filter(relation)
    relation = apply_cleared_filter(relation)

    apply_sort(relation)
  end

  private

  def value(key)
    @params[key] || @params[key.to_s]
  end

  def apply_date_filter(relation)
    raw_start_date = value(:start_date)
    raw_end_date = value(:end_date)
    return relation.where(occurred_on: @default_date_range) if raw_start_date.blank? && raw_end_date.blank?

    start_date = parse_date(raw_start_date)
    end_date = parse_date(raw_end_date)
    return relation.none if raw_start_date.present? && start_date.nil?
    return relation.none if raw_end_date.present? && end_date.nil?

    relation = relation.where("transactions.occurred_on >= ?", start_date) if start_date
    relation = relation.where("transactions.occurred_on <= ?", end_date) if end_date
    relation
  end

  def apply_search(relation)
    query = value(:q).to_s.strip
    return relation if query.blank?

    escaped_query = ActiveRecord::Base.sanitize_sql_like(query)
    conditions = <<~SQL.squish
      (transactions.description ILIKE :query
      OR accounts.name ILIKE :query
      OR categories.name ILIKE :query
      OR EXISTS (
        SELECT 1
        FROM statement_entries
        WHERE statement_entries.transaction_id = transactions.id
        AND (
          statement_entries.raw_description ILIKE :query
          OR statement_entries.normalized_description ILIKE :query
          OR statement_entries.merchant_key ILIKE :query
          OR statement_entries.source_transaction_id ILIKE :query
        )
      ))
    SQL
    binds = { query: "%#{escaped_query}%" }

    if (amount_cents = parse_amount_cents(query))
      conditions = "(#{conditions} OR transactions.amount_cents = :amount_cents)"
      binds[:amount_cents] = amount_cents
    end

    relation.left_joins(:account, :category).where(conditions, binds)
  end

  def apply_id_filter(relation, key)
    raw_id = value(key)
    return relation if raw_id.blank?

    id = Integer(raw_id, exception: false)
    return relation.none unless id&.positive?

    relation.where(key => id)
  end

  def apply_flow_filter(relation)
    case value(:flow)
    when "inflow"
      relation.where("transactions.amount_cents > 0")
    when "outflow"
      relation.where("transactions.amount_cents < 0")
    else
      relation
    end
  end

  def apply_reconciliation_filter(relation)
    case value(:reconciliation_status)
    when "reconciled"
      relation.where("transactions.reconciled_at IS NOT NULL OR transactions.reconciliation_id IS NOT NULL")
    when "unreconciled"
      relation.where(reconciled_at: nil, reconciliation_id: nil)
    else
      relation
    end
  end

  def apply_cleared_filter(relation)
    case value(:cleared_status)
    when "cleared"
      relation.where(cleared: true)
    when "uncleared"
      relation.where(cleared: [ false, nil ])
    else
      relation
    end
  end

  def apply_sort(relation)
    return relation.order(occurred_on: :desc, id: :desc) unless sort_key

    relation = relation.left_joins(:account) if sort_key == "account"
    relation = relation.left_joins(:category) if sort_key == "category"

    node = sort_node
    ordered_node = direction == "asc" ? node.asc : node.desc
    relation.reorder(ordered_node.nulls_last, Transaction.arel_table[:id].desc)
  end

  def normalized_direction
    return unless sort_key

    value(:direction).presence_in(DIRECTIONS) || DEFAULT_DIRECTIONS.fetch(sort_key)
  end

  def sort_node
    transactions = Transaction.arel_table

    case sort_key
    when "date" then transactions[:occurred_on]
    when "description" then lower(transactions[:description])
    when "account" then lower(Account.arel_table[:name])
    when "category" then lower(Category.arel_table[:name])
    when "amount" then transactions[:amount_cents]
    end
  end

  def lower(attribute)
    Arel::Nodes::NamedFunction.new("LOWER", [ attribute ])
  end

  def parse_date(raw_date)
    Date.iso8601(raw_date.to_s) if raw_date.present?
  rescue Date::Error
    nil
  end

  def parse_amount_cents(query)
    return unless query.match?(/\A[+-]?\d+(?:\.\d{1,2})?\z/)

    amount = BigDecimal(query) * 100
    amount.to_i if amount.frac.zero?
  rescue ArgumentError
    nil
  end
end
