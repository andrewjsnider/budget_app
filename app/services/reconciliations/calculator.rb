module Reconciliations
  class Calculator
    Result = Data.define(
      :starting_balance_cents,
      :activity_cents,
      :computed_ending_balance_cents,
      :difference_cents
    )

    def initialize(account:, starts_on:, ends_on:, transactions:, statement_ending_balance_cents:)
      @account = account
      @starts_on = starts_on
      @ends_on = ends_on
      @transactions = transactions
      @statement_ending_balance_cents = statement_ending_balance_cents
    end

    def call
      activity_cents = @transactions.sum(&:amount_cents)
      computed_ending_balance_cents = starting_balance_cents + activity_cents

      Result.new(
        starting_balance_cents: starting_balance_cents,
        activity_cents: activity_cents,
        computed_ending_balance_cents: computed_ending_balance_cents,
        difference_cents: @statement_ending_balance_cents - computed_ending_balance_cents
      )
    end

    private

    def starting_balance_cents
      @starting_balance_cents ||= begin
        previous = @account.reconciliations
          .where(status: "finalized")
          .where("ends_on < ?", @starts_on)
          .order(ends_on: :desc, id: :desc)
          .first

        if previous
          gap_activity = @account.transactions
            .where("occurred_on > ? AND occurred_on < ?", previous.ends_on, @starts_on)
            .sum(:amount_cents)
          previous.statement_ending_balance_cents + gap_activity
        else
          @account.transactions.where("occurred_on < ?", @starts_on).sum(:amount_cents)
        end
      end
    end
  end
end
