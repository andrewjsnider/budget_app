class AccountMonthSummary
  attr_reader :account, :month

  def initialize(account:, month:)
    @account = account
    @month = month.beginning_of_month
  end

  def opening_balance_cents
    account.balance_cents(as_of: month - 1.day)
  end

  def activity_cents
    account.transactions.where(occurred_on: month..month.end_of_month).sum(:amount_cents)
  end

  def ending_balance_cents
    opening_balance_cents + activity_cents
  end
end
