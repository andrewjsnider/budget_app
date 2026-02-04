class ReconciliationsController < ApplicationController
  def new
    @account = Account.find(params[:account_id])
    @starts_on = (params[:starts_on].presence && Date.parse(params[:starts_on])) || Date.current.beginning_of_month
    @ends_on = (params[:ends_on].presence && Date.parse(params[:ends_on])) || Date.current.end_of_month

    @transactions = @account.transactions
      .where(occurred_on: @starts_on..@ends_on)
      .where(reconciled_at: nil)
      .order(:occurred_on, :id)

    @starting_balance_cents = @account.transactions.where("reconciled_at IS NOT NULL").sum(:amount_cents)
    @cleared_sum_cents = @transactions.where(cleared: true).sum(:amount_cents)
  end

  def create
    @account = Account.find(params[:account_id])
    starts_on = Date.parse(params[:starts_on])
    ends_on = Date.parse(params[:ends_on])
    statement_ending_balance_cents = parse_cents(params[:statement_ending_balance])

    ids = Array(params[:cleared_transaction_ids]).map(&:to_i)
    @account.transactions.where(id: ids).update_all(cleared: true)

    starting_balance_cents = @account.transactions.where("reconciled_at IS NOT NULL").sum(:amount_cents)
    cleared_sum_cents = @account.transactions.where(occurred_on: starts_on..ends_on, reconciled_at: nil, cleared: true).sum(:amount_cents)
    difference_cents = statement_ending_balance_cents - (starting_balance_cents + cleared_sum_cents)

    reconciliation = @account.reconciliations.create!(
      starts_on: starts_on,
      ends_on: ends_on,
      statement_ending_balance_cents: statement_ending_balance_cents
    )

    if difference_cents == 0
      now = Time.current
      @account.transactions.where(occurred_on: starts_on..ends_on, reconciled_at: nil, cleared: true).update_all(reconciled_at: now)
      reconciliation.update!(reconciled_at: now)
      redirect_to account_reconciliation_path(@account, reconciliation), notice: "Reconciled."
    else
      redirect_to new_account_reconciliation_path(@account, starts_on: starts_on, ends_on: ends_on),
        alert: "Not balanced. Difference: #{format("$%.2f", difference_cents / 100.0)}"
    end
  end

  def show
    @account = Account.find(params[:account_id])
    @reconciliation = @account.reconciliations.find(params[:id])
  end

  private

  def parse_cents(raw)
    s = raw.to_s.strip
    return 0 if s.blank?
    (s.to_f * 100.0).round
  end
end
