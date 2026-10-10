require "test_helper"
require "digest"
require "fileutils"
require "tmpdir"

class StatementsStageImportTest < ActiveSupport::TestCase
  def setup
    @account = create(:account, import_key: "primary-checking")
    @finance_root = Pathname.new(Dir.mktmpdir("budget-finance"))
    @statement_dir = @finance_root.join("2026-10")
    @statement_dir.mkpath
    @statement_path = @statement_dir.join("checking.csv")
  end

  def teardown
    FileUtils.remove_entry(@finance_root) if @finance_root&.exist?
  end

  def test_apply_persists_import_and_entries_without_creating_ledger_transactions
    write_statement <<~CSV
      Date,Description,Amount
      2026-10-01,Paycheck,1000.00
      10/02/2026,Groceries,-45.67
    CSV

    result = nil
    assert_no_difference "Transaction.count" do
      assert_difference "StatementImport.count", 1 do
        assert_difference "StatementEntry.count", 2 do
          result = stage(started_on: Date.new(2026, 10, 1), ended_on: Date.new(2026, 10, 31), ending_balance: 95_433)
        end
      end
    end

    statement_import = StatementImport.find(result.fetch(:statement_import_id))
    assert_equal "staged", statement_import.status
    assert_equal "2026-10/checking.csv", statement_import.source_path
    assert_equal "checking.csv", statement_import.source_filename
    assert_equal 2, statement_import.row_count
    assert_equal 2, statement_import.parsed_count
    assert_equal 0, statement_import.failed_count
    assert_equal 95_433, statement_import.statement_ending_balance_cents
    assert_equal [ -4567, 100_000 ], statement_import.statement_entries.order(:amount_cents).pluck(:amount_cents)
    assert_equal 100_000, result.fetch(:positive_total_cents)
    assert_equal(-4567, result.fetch(:negative_total_cents))
    assert_equal Date.new(2026, 10, 1), result.fetch(:detected_start_date)
    assert_equal Date.new(2026, 10, 2), result.fetch(:detected_end_date)
  end

  def test_exact_same_file_is_an_idempotent_rerun
    write_statement basic_statement

    first = stage
    second = stage

    assert_equal "staged", first.fetch(:status)
    assert_equal "exact_rerun", second.fetch(:status)
    assert second.fetch(:exact_rerun)
    assert_equal first.fetch(:statement_import_id), second.fetch(:statement_import_id)
    assert_equal 1, StatementImport.count
    assert_equal 1, StatementEntry.count
  end

  def test_two_identical_rows_both_survive_with_duplicate_ordinals
    write_statement <<~CSV
      Date,Description,Amount
      2026-10-03,Coffee,-4.25
      2026-10-03,Coffee,-4.25
    CSV

    result = stage
    entries = StatementImport.find(result.fetch(:statement_import_id)).statement_entries.order(:source_row_number)

    assert_equal 2, entries.size
    assert_equal [ 2, 3 ], entries.map(&:source_row_number)
    assert_equal 1, entries.map(&:raw_payload).uniq.size
    assert_equal 2, entries.map(&:source_identity).uniq.size
  end

  def test_institution_transaction_id_takes_priority_in_source_identity
    write_statement <<~CSV
      Date,Description,Amount,Transaction ID
      2026-10-03,Coffee,-4.25,bank-100
      2026-10-03,Coffee,-4.25,bank-101
    CSV

    result = stage
    entries = StatementImport.find(result.fetch(:statement_import_id)).statement_entries.order(:source_row_number)

    assert_equal [ "bank-100", "bank-101" ], entries.map(&:source_transaction_id)
    assert_equal 2, entries.map(&:source_identity).uniq.size

    first_row = {
      source_transaction_id: "bank-100",
      raw_payload: entries.first.raw_payload
    }
    expected = Statements::SourceIdentity.call(
      account_id: @account.id,
      file_sha256: result.fetch(:file_sha256),
      base_key: Statements::SourceIdentity.base_key(first_row),
      occurrence: 1
    )
    assert_equal expected, entries.first.source_identity
  end

  def test_malformed_rows_are_preserved_and_reported_without_silent_drops
    write_statement <<~CSV
      Date,Description,Amount
      2026-10-01,Valid,-10.00
      not-a-date,Bad date,-2.00
      2026-10-03,Bad amount,not-money
    CSV

    result = stage
    statement_import = StatementImport.find(result.fetch(:statement_import_id))

    assert_equal "failed", result.fetch(:status)
    assert_equal 3, result.fetch(:rows_seen)
    assert_equal 1, result.fetch(:rows_parsed)
    assert_equal 2, result.fetch(:rows_failed)
    assert_equal 3, statement_import.statement_entries.count
    assert_equal [ "invalid_date", "invalid_amount" ], result.fetch(:errors).pluck(:error_code)

    failed_entries = statement_import.statement_entries.where(status: "failed").order(:source_row_number)
    assert_equal [ 3, 4 ], failed_entries.pluck(:source_row_number)
    assert failed_entries.all? { |entry| entry.raw_payload.fetch("values").any? }
  end

  def test_missing_values_have_specific_failure_codes
    write_statement <<~CSV
      Date,Description,Amount
      ,Missing date,-1.00
      2026-10-02,Missing amount,
    CSV

    result = stage

    assert_equal 2, result.fetch(:rows_seen)
    assert_equal [ "missing_date", "missing_amount" ], result.fetch(:errors).pluck(:error_code)
  end

  def test_dry_run_parses_everything_and_writes_nothing
    write_statement basic_statement

    result = nil
    assert_no_difference [ "StatementImport.count", "StatementEntry.count", "Transaction.count" ] do
      result = stage(dry_run: true)
    end

    assert_equal "dry_run_staged", result.fetch(:status)
    assert_nil result.fetch(:statement_import_id)
    assert_equal 1, result.fetch(:rows_seen)
  end

  def test_file_hash_is_the_exact_source_bytes_and_source_is_not_modified
    source = basic_statement
    write_statement source
    before_stat = @statement_path.stat

    result = stage(dry_run: true)

    assert_equal Digest::SHA256.hexdigest(source), result.fetch(:file_sha256)
    assert_equal source, @statement_path.binread
    assert_equal before_stat.size, @statement_path.stat.size
    assert_equal before_stat.mtime, @statement_path.stat.mtime
  end

  def test_tab_delimited_posting_date_format_is_supported
    write_statement <<~TSV
      Details\tPosting Date\tDescription\tAmount\tType
      DEBIT\t10/06/2026\tUTILITY PAYMENT\t-122.41\tMISC_DEBIT
    TSV

    result = stage
    entry = StatementImport.find(result.fetch(:statement_import_id)).statement_entries.sole

    assert_equal "parsed", entry.status
    assert_equal Date.new(2026, 10, 6), entry.posted_on
    assert_equal(-12_241, entry.amount_cents)
  end

  def test_unsupported_headers_are_a_fatal_parser_error_without_writes
    write_statement <<~CSV
      Description,Value
      Groceries,-10.00
    CSV

    assert_no_difference [ "StatementImport.count", "StatementEntry.count" ] do
      assert_raises(Statements::Parsers::GenericSignedCsv::FatalError) { stage }
    end
  end

  def test_unknown_parser_and_unknown_account_fail_without_writes
    write_statement basic_statement

    assert_no_difference "StatementImport.count" do
      assert_raises(Statements::Parsers::UnknownParser) { stage(parser_key: "unknown") }
      assert_raises(Statements::StageImport::UnknownAccount) { stage(account: "missing-account") }
    end
  end

  def test_file_outside_finance_root_and_symlink_escape_are_rejected
    outside_dir = Pathname.new(Dir.mktmpdir("outside-finance"))
    outside_file = outside_dir.join("outside.csv")
    outside_file.binwrite(basic_statement)

    assert_raises(Statements::StageImport::InvalidSource) { stage(file_path: outside_file) }

    escaped_link = @statement_dir.join("escaped.csv")
    File.symlink(outside_file, escaped_link)
    assert_raises(Statements::StageImport::InvalidSource) { stage(file_path: escaped_link) }

    write_statement basic_statement
    traversal_path = File.join(@statement_dir.to_s, "..", "2026-10", "checking.csv")
    assert_raises(Statements::StageImport::InvalidSource) { stage(file_path: traversal_path) }

    assert_raises(Statements::StageImport::InvalidSource) do
      Statements::StageImport.call(
        account: @account,
        file_path: Rails.root.join("README.md"),
        parser_key: "generic_signed_csv",
        dry_run: true,
        finance_root: Rails.root
      )
    end
  ensure
    FileUtils.remove_entry(outside_dir) if outside_dir&.exist?
  end

  def test_import_key_cannot_change_after_staging
    write_statement basic_statement
    stage

    assert_not @account.update(import_key: "renamed-account")
    assert_includes @account.errors[:import_key], "cannot change after a statement has been staged"
  end

  private

  def basic_statement
    <<~CSV
      Date,Description,Amount
      2026-10-01,Groceries,-10.00
    CSV
  end

  def write_statement(contents)
    @statement_path.binwrite(contents)
  end

  def stage(dry_run: false, parser_key: "generic_signed_csv", account: @account,
            file_path: @statement_path, started_on: nil, ended_on: nil, ending_balance: nil)
    Statements::StageImport.call(
      account: account,
      file_path: file_path,
      parser_key: parser_key,
      started_on: started_on,
      ended_on: ended_on,
      statement_ending_balance_cents: ending_balance,
      dry_run: dry_run,
      finance_root: @finance_root
    )
  end
end
