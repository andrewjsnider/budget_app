# test/services/transactions/csv_import_test.rb
require "test_helper"

class TransactionsCsvImportTest < ActiveSupport::TestCase
  def setup
    @account = FactoryBot.create(:account)
    @category = FactoryBot.create(:category, name: "Uncategorized")
  end

  def test_imports_and_skips_duplicates
    csv = <<~CSV
      Date,Description,Amount
      2026-03-01,Store,-12.34
      2026-03-02,Paycheck,100.00
    CSV

    r1 = Transactions::CsvImport.call(account: @account, csv_text: csv, default_category: @category)
    assert r1[:ok]
    assert_equal 2, r1[:imported]
    assert_equal 0, r1[:skipped]

    r2 = Transactions::CsvImport.call(account: @account, csv_text: csv, default_category: @category)
    assert r2[:ok]
    assert_equal 0, r2[:imported]
    assert_equal 2, r2[:skipped]
  end
end
