class TransactionsBulkCategorizationsController < ApplicationController
  def show
    @account = Account.find(params[:account_id])
    @month = params[:month].present? ? Date.strptime(params[:month], "%Y-%m") : Date.current.beginning_of_month
    @categories = Category.order(:group, :name)

    txs = @account.transactions
      .where(occurred_on: @month..@month.end_of_month)
      .joins(:category)
      .where(categories: { name: "Uncategorized" })
      .order(occurred_on: :desc)

    @groups = txs.group_by { |t| normalize_merchant(t.description) }
  end

  def update
    @account = Account.find(params[:account_id])
    @month = params[:month].present? ? Date.strptime(params[:month], "%Y-%m") : Date.current.beginning_of_month

    merchant_key = params.fetch(:merchant_key)
    category_id  = params.fetch(:category_id)
    save_rule    = params[:save_rule] == "1"

    category = Category.find(category_id)

    txs = @account.transactions
      .where(occurred_on: @month..@month.end_of_month)
      .joins(:category)
      .where(categories: { name: "Uncategorized" })

    to_update = txs.select { |t| normalize_merchant(t.description) == merchant_key }

    Transaction.transaction do
      to_update.each { |t| t.update!(category: category) }

      if save_rule
        PayeeRule.create!(
          pattern: merchant_key,
          match_type: "contains",
          category: category,
          active: true
        )
      end
    end

    redirect_to account_uncategorized_path(@account, month: @month.strftime("%Y-%m")),
                notice: "Updated #{to_update.size} transactions."
  end

  private

  def normalize_merchant(desc)
    d = desc.to_s.strip.gsub(/\s+/, " ")
    d = d.sub(/\APOS DEBIT\s+/, "")
    d = d.sub(/\AACH DEBIT\s+/, "")
    d = d.sub(/\AONLINE\s+/, "")
    d[0, 40].upcase
  end
end
