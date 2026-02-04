class AccountProjection
  Occurrence = Struct.new(:date, :amount_cents, :label)

  def initialize(account:, from:, to:)
    @account = account
    @from = from
    @to = to
  end

  def occurrences
    (posted_occurrences + projected_income_occurrences + projected_expense_occurrences).sort_by(&:date)
  end

  def starting_balance_cents
    rec = last_reconciled

    if rec
      rec.statement_ending_balance_cents + @account.transactions
        .where("occurred_on > ?", rec.ends_on)
        .where("occurred_on < ?", @from)
        .sum(:amount_cents)
    else
      @account.transactions.where("occurred_on < ?", @from).sum(:amount_cents)
    end
  end

  def daily_balances
    bal = starting_balance_cents
    out = {}
    day = @from

    indexed = occurrences.group_by(&:date)

    while day <= @to
      indexed.fetch(day, []).each { |o| bal += o.amount_cents }
      out[day] = bal
      day = day + 1.day
    end

    out
  end

  private

  def posted_occurrences
    @account.transactions.where(occurred_on: @from..@to).order(:occurred_on, :id).map do |t|
      Occurrence.new(t.occurred_on, t.amount_cents, t.description.presence || "Transaction")
    end
  end

  def projected_income_occurrences
    IncomeEstimate.includes(income_source: [:account]).where(active: [true, nil]).flat_map do |rule|
      next [] unless rule.income_source.account_id == @account.id
      expand_rule(rule, label_prefix: rule.income_source.name, amount_cents: rule.estimated_amount_cents)
    end
  end

  def projected_expense_occurrences
    RecurringExpense.includes(:account).where(active: [true, nil], account_id: @account.id).flat_map do |rule|
      expand_rule(rule, label_prefix: rule.name, amount_cents: rule.estimated_amount_cents)
    end
  end

  def expand_rule(rule, label_prefix:, amount_cents:)
    start_on = [rule.start_on, @from].max
    end_on = rule.end_on.present? ? [rule.end_on, @to].min : @to
    return [] if start_on > end_on

    dates = case rule.cadence
    when "weekly"
      step_days = 7 * (rule.interval || 1)
      first = next_weekday_on_or_after(start_on, rule.weekday)
      build_by_step(first, end_on, step_days)
    when "biweekly"
      step_days = 14 * (rule.interval || 1)
      first = next_weekday_on_or_after(start_on, rule.weekday)
      build_by_step(first, end_on, step_days)
    when "monthly"
      first = next_day_of_month_on_or_after(start_on, rule.day_of_month || 1)
      build_by_month(first, end_on, rule.interval || 1, rule.day_of_month || 1)
    when "quarterly"
      first = next_day_of_month_on_or_after(start_on, rule.day_of_month || 1)
      build_by_month(first, end_on, 3 * (rule.interval || 1), rule.day_of_month || 1)
    when "yearly"
      first = next_day_of_month_on_or_after(start_on, rule.day_of_month || 1)
      build_by_month(first, end_on, 12 * (rule.interval || 1), rule.day_of_month || 1)
    else
      []
    end

    dates.map { |d| Occurrence.new(d, amount_cents, label_prefix) }
  end

  def build_by_step(first_date, end_on, step_days)
    return [] if first_date.nil?
    out = []
    d = first_date
    while d <= end_on
      out << d
      d = d + step_days.days
    end
    out
  end

  def build_by_month(first_date, end_on, step_months, day_of_month)
    return [] if first_date.nil?
    out = []
    d = first_date
    while d <= end_on
      out << d
      d = safe_day_in_month(d.next_month(step_months), day_of_month)
    end
    out
  end

  def next_weekday_on_or_after(date, weekday)
    return nil if weekday.nil?
    d = date
    d += 1.day while d.wday != weekday
    d
  end

  def next_day_of_month_on_or_after(date, day_of_month)
    d = safe_day_in_month(date, day_of_month)
    d < date ? safe_day_in_month(date.next_month, day_of_month) : d
  end

  def safe_day_in_month(date, day_of_month)
    last = date.end_of_month.day
    Date.new(date.year, date.month, [day_of_month, last].min)
  end

  def last_reconciled
    @account.reconciliations
      .where.not(reconciled_at: nil)
      .order(ends_on: :desc, reconciled_at: :desc, id: :desc)
      .first
  end
end
