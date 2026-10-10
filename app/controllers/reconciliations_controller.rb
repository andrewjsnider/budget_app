class ReconciliationsController < ApplicationController
  def new
    @account = Account.find(params[:account_id])
    @starts_on = (params[:starts_on].presence && Date.parse(params[:starts_on])) || Date.current.beginning_of_month
    @ends_on = (params[:ends_on].presence && Date.parse(params[:ends_on])) || Date.current.end_of_month

    @transactions = @account.transactions
      .where(occurred_on: @starts_on..@ends_on)
      .where(reconciled_at: nil)
      .where(reconciliation_id: nil)
      .order(:occurred_on, :id)

    @starting_balance_cents = Reconciliations::Calculator.new(
      account: @account,
      starts_on: @starts_on,
      ends_on: @ends_on,
      transactions: [],
      statement_ending_balance_cents: 0
    ).call.starting_balance_cents
    @cleared_sum_cents = @transactions.where(cleared: true).sum(:amount_cents)
  rescue Date::Error
    redirect_to new_account_reconciliation_path(@account), alert: "Invalid reconciliation dates."
  end

  def create
    @account = Account.find(params[:account_id])
    starts_on = Date.parse(params[:starts_on])
    ends_on = Date.parse(params[:ends_on])
    statement_ending_balance_cents = parse_cents(params[:statement_ending_balance])

    raise ArgumentError, "End date must be on or after start date" if starts_on > ends_on

    requested_ids = Array(params[:cleared_transaction_ids]).map { |id| Integer(id, 10) }.uniq
    candidates = @account.transactions
      .where(occurred_on: starts_on..ends_on, reconciled_at: nil, reconciliation_id: nil)
    selected = candidates.where(id: requested_ids).order(:occurred_on, :id).to_a
    raise ArgumentError, "One or more selected transactions are not eligible" unless selected.size == requested_ids.size

    reconciliation = nil
    Transaction.transaction do
      candidates.update_all(cleared: false)
      @account.transactions.where(id: requested_ids).update_all(cleared: true) if requested_ids.any?

      result = Reconciliations::Calculator.new(
        account: @account,
        starts_on: starts_on,
        ends_on: ends_on,
        transactions: selected,
        statement_ending_balance_cents: statement_ending_balance_cents
      ).call

      finalized = result.difference_cents.zero?
      now = Time.current if finalized
      reconciliation = @account.reconciliations.create!(
        starts_on: starts_on,
        ends_on: ends_on,
        statement_ending_balance_cents: statement_ending_balance_cents,
        starting_balance_cents: result.starting_balance_cents,
        computed_ending_balance_cents: result.computed_ending_balance_cents,
        difference_cents: result.difference_cents,
        status: finalized ? "finalized" : "draft",
        reconciled_at: now
      )

      if finalized && requested_ids.any?
        @account.transactions.where(id: requested_ids).update_all(
          reconciliation_id: reconciliation.id,
          reconciled_at: now
        )
      end
    end

    if reconciliation.finalized?
      redirect_to account_reconciliation_path(@account, reconciliation), notice: "Reconciled exactly."
    else
      redirect_to account_reconciliation_path(@account, reconciliation),
        alert: "Not balanced. Difference: #{format_cents(reconciliation.difference_cents)}"
    end
  rescue Date::Error, ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to new_account_reconciliation_path(@account), alert: e.message
  end

  def show
    @account = Account.find(params[:account_id])
    @reconciliation = @account.reconciliations.find(params[:id])
  end

  private

  def parse_cents(raw)
    s = raw.to_s.strip
    raise ArgumentError, "Statement ending balance is required" if s.blank?

    (BigDecimal(s.delete(",$")) * 100).round.to_i
  rescue ArgumentError
    raise ArgumentError, "Statement ending balance is invalid"
  end

  def format_cents(cents)
    format("$%.2f", cents / 100.0)
  end
end
