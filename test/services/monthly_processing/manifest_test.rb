require "test_helper"
require "fileutils"
require "tmpdir"

class MonthlyProcessingManifestTest < ActiveSupport::TestCase
  def setup
    @account = create(:account, import_key: "primary-checking")
    @source_root = Pathname.new(Dir.mktmpdir("monthly-manifest")).realpath
    @statements_dir = @source_root.join("statements")
    @statements_dir.mkpath
    @statement_path = @statements_dir.join("checking.csv")
    @statement_path.binwrite("Date,Description,Amount\n2026-10-05,Groceries,-12.34\n")
    write_manifest
  end

  def teardown
    FileUtils.remove_entry(@source_root) if @source_root&.exist?
  end

  test "clean manifest resolves accounts parsers dates balances and files" do
    result = load_manifest
    statement = result.statements.sole

    assert_equal Date.new(2026, 10, 1), result.month
    assert_equal "2026-10", result.month_key
    assert_equal @source_root, result.source_root
    assert_equal @account, statement.account
    assert_equal "statements/checking.csv", statement.source_path
    assert_equal "generic_signed_csv", statement.parser_key
    assert_equal "1", statement.parser_version
    assert_equal Date.new(2026, 10, 1), statement.started_on
    assert_equal Date.new(2026, 10, 31), statement.ended_on
    assert_equal 48_123, statement.statement_ending_balance_cents
    assert_match(/\A[0-9a-f]{64}\z/, result.input_digest)
  end

  test "unknown account and parser are rejected" do
    write_manifest(account: "missing-account")
    error = assert_raises(MonthlyProcessing::Manifest::InvalidManifest) { load_manifest }
    assert_includes error.message, "Unknown active account"

    write_manifest(parser: "mystery_parser")
    error = assert_raises(MonthlyProcessing::Manifest::InvalidManifest) { load_manifest }
    assert_includes error.message, "Unknown statement parser"
  end

  test "missing and unsafe source files are rejected" do
    write_manifest(file: "statements/missing.csv")
    assert_raises(MonthlyProcessing::PathSafety::UnsafePath) { load_manifest }

    write_manifest(file: "../outside.csv")
    assert_raises(MonthlyProcessing::PathSafety::UnsafePath) { load_manifest }

    assert_raises(MonthlyProcessing::PathSafety::UnsafePath) do
      MonthlyProcessing::Manifest.call(month: "2026-10", source_dir: Rails.root)
    end
  end

  test "unsafe statement symlink is rejected" do
    linked = @statements_dir.join("linked.csv")
    File.symlink(@statement_path, linked)
    write_manifest(file: "statements/linked.csv")

    assert_raises(MonthlyProcessing::PathSafety::UnsafePath) { load_manifest }
  end

  test "input digest is deterministic and includes exact statement bytes" do
    first = load_manifest.input_digest
    second = load_manifest.input_digest
    assert_equal first, second

    @statement_path.binwrite("Date,Description,Amount\n2026-10-05,Groceries,-12.35\n")
    assert_not_equal first, load_manifest.input_digest
  end

  test "duplicate account and file definitions are rejected" do
    statement = statement_yaml
    @source_root.join("manifest.yml").binwrite(<<~YAML)
      month: 2026-10
      statements:
      #{statement.lines.map { |line| "  #{line}" }.join}#{statement.lines.map { |line| "  #{line}" }.join}
    YAML

    error = assert_raises(MonthlyProcessing::Manifest::InvalidManifest) { load_manifest }
    assert_includes error.message, "duplicate statement definitions"
  end

  private

  def load_manifest
    MonthlyProcessing::Manifest.call(month: "2026-10", source_dir: @source_root)
  end

  def write_manifest(account: "primary-checking", file: "statements/checking.csv", parser: "generic_signed_csv")
    @source_root.join("manifest.yml").binwrite(<<~YAML)
      month: 2026-10
      statements:
        - account: #{account}
          file: #{file}
          parser: #{parser}
          starts_on: 2026-10-01
          ends_on: 2026-10-31
          ending_balance: "481.23"
    YAML
  end

  def statement_yaml
    <<~YAML
      - account: primary-checking
        file: statements/checking.csv
        parser: generic_signed_csv
        starts_on: 2026-10-01
        ends_on: 2026-10-31
        ending_balance: "481.23"
    YAML
  end
end
