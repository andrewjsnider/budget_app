class TransactionsImportsController < ApplicationController
  def new
    @account = Account.find(params[:account_id])
  end

  def create
    @account = Account.find(params[:account_id])

    file = params[:csv_file]
    unless file&.respond_to?(:read)
      redirect_to new_account_transactions_import_path(@account), alert: "Please choose a CSV file."
      return
    end

    category = Category.find_or_create_by!(name: "Uncategorized") do |c|
      c.kind = "expense"
      c.group = "Imported"
      c.archived = false
    end

    result = Transactions::CsvImport.call(
      account: @account,
      csv_text: file.read,
      default_category: category
    )

    unless result[:ok]
      flash.now[:alert] = result[:error]
      render :new, status: :unprocessable_entity
      return
    end

    notice = "Imported #{result[:imported]} transactions. Skipped #{result[:skipped]} duplicates."
    if result[:failed].to_i > 0
      notice += " Failed #{result[:failed]} rows."
      errs = Array(result[:errors])
      notice += " #{errs.join(' | ')}" if errs.any?
    end

    redirect_to account_path(@account), notice: notice
  end
end
