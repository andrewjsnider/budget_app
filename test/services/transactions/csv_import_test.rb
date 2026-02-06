# test/services/transactions/csv_import_test.rb
require "test_helper"

class TransactionsCsvImportTest < ActiveSupport::TestCase
  def setup
    @account = FactoryBot.create(:account)
    @uncat = FactoryBot.create(:category, name: "Uncategorized", kind: "expense", group: "Imported", archived: false)
    @income = FactoryBot.create(:category, name: "Imported Income", kind: "income", group: "Imported", archived: false)
    @utilities = FactoryBot.create(:category, name: "Utilities", kind: "expense", group: "Bills", archived: false)
  end

  def test_imports_and_skips_duplicates
    csv = <<~CSV
      Date,Description,Amount
      2026-03-01,Store,-12.34
      2026-03-02,Paycheck,100.00
    CSV

    r1 = Transactions::CsvImport.call(account: @account, csv_text: csv, default_category: @uncat)
    assert r1[:ok]
    assert_equal 2, r1[:imported]
    assert_equal 0, r1[:skipped]

    r2 = Transactions::CsvImport.call(account: @account, csv_text: csv, default_category: @uncat)
    assert r2[:ok]
    assert_equal 0, r2[:imported]
    assert_equal 2, r2[:skipped]
  end

  def test_import_tsv_amounts_are_positive_and_direction_sets_category
    tsv = +"Details\tPosting Date\tDescription\tAmount\tType\tBalance\n"
    tsv << "DSLIP\t02/06/2026\tONLINE DEPOSIT\t3200.00\tCHECK_DEPOSIT\t\n"
    tsv << "DEBIT\t02/06/2026\tPOS DEBIT COMCAST / XFINITY\t-122.41\tMISC_DEBIT\t\n"

    result = Transactions::CsvImport.call(account: @account, csv_text: tsv, default_category: @uncat)

    assert result[:ok]
    assert_equal 2, result[:imported]
    assert_equal 0, result[:failed]

    txs = @account.transactions.order(:occurred_on, :id)
    assert_equal 2, txs.size

    income_tx = txs.first
    assert_equal 320_000, income_tx.amount_cents
    assert_equal @income.name, income_tx.category.name

    expense_tx = txs.second
    assert_equal 12_241, expense_tx.amount_cents
    assert_equal @uncat.name, expense_tx.category.name
  end

  def test_import_applies_payee_rule_category
    PayeeRule.create!(pattern: "COMCAST", match_type: "contains", category: @utilities, active: true)

    tsv = +"Details\tPosting Date\tDescription\tAmount\tType\tBalance\n"
    tsv << "DEBIT\t02/06/2026\tPOS DEBIT COMCAST / XFINITY\t-122.41\tMISC_DEBIT\t\n"

    result = Transactions::CsvImport.call(account: @account, csv_text: tsv, default_category: @uncat)

    assert result[:ok]
    assert_equal 1, result[:imported]

    tx = @account.transactions.first
    assert_equal 12_241, tx.amount_cents
    assert_equal @utilities.id, tx.category_id
  end

  def test_import_skips_duplicates_by_import_hash
    tsv = +"Details\tPosting Date\tDescription\tAmount\tType\tBalance\n"
    tsv << "DEBIT\t02/06/2026\tSAFEWAY #2640\t-23.51\tDEBIT_CARD\t\n"

    r1 = Transactions::CsvImport.call(account: @account, csv_text: tsv, default_category: @uncat)
    r2 = Transactions::CsvImport.call(account: @account, csv_text: tsv, default_category: @uncat)

    assert r1[:ok]
    assert r2[:ok]
    assert_equal 1, r1[:imported]
    assert_equal 0, r1[:skipped]
    assert_equal 0, r2[:imported]
    assert_equal 1, r2[:skipped]
  end
end
