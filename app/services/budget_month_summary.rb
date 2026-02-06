class BudgetMonthSummary
  def initialize(budget_month)
    @budget_month = budget_month
  end

  def income_cents
    transactions.joins(:category).where(categories: { kind: "income" }).sum(:amount_cents)
  end


  def assigned_cents
    @budget_month.budget_items.sum(:assigned_cents)
  end

  def to_assign_cents
    income_cents - assigned_cents
  end

  private

  def transactions
    Transaction.where(
      occurred_on: @budget_month.month..@budget_month.month.end_of_month
    )
  end
end
