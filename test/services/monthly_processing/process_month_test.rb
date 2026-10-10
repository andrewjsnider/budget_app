require "test_helper"
require "fileutils"
require "json"
require "tmpdir"

class MonthlyProcessingProcessMonthTest < ActiveSupport::TestCase
  FIXED_TIME = Time.utc(2026, 11, 1, 8, 30, 0)

  def setup
    @account = create(:account, import_key: "primary-checking")
    @category = create(:category)
    @source_root = Pathname.new(Dir.mktmpdir("monthly-processing")).realpath
    @statements_dir = @source_root.join("statements")
    @statements_dir.mkpath
    @statement_path = @statements_dir.join("checking.csv")
    write_statement(amount: "-10.00")
    write_manifest(ending_balance: "90.00")
  end

  def teardown
    FileUtils.remove_entry(@source_root) if @source_root&.exist?
  end

  test "dry run previews an unstaged statement with zero database writes" do
    result = nil
    counts = [
      "StatementImport.count",
      "StatementEntry.count",
      "StatementEntryResolution.count",
      "Transaction.count",
      "Reconciliation.count",
      "MonthlyProcessingRun.count",
      "MonthlyProcessingRunStatement.count"
    ]
    assert_no_difference counts do
      result = process(dry_run: true)
    end

    process_run = read_json(result, "process_run.json")
    statements = read_json(result, "statements.json").fetch("statements")
    unresolved = read_json(result, "unresolved_items.json").fetch("items")
    assert process_run.fetch("dry_run")
    assert_nil process_run.fetch("run_id")
    assert_equal 1, process_run.fetch("staged_count")
    assert_nil statements.sole.fetch("statement_import_id")
    assert_includes unresolved.pluck("type"), "unresolved_no_candidate"
    assert_not_includes File.binread(result.fetch(:output_path).then { |path| Pathname.new(path).join("unresolved_items.json") }), "raw_payload"
  end

  test "apply mode stages safely and persists an auditable blocked run" do
    result = nil
    assert_difference "StatementImport.count", 1 do
      assert_difference "StatementEntry.count", 1 do
        assert_difference "MonthlyProcessingRun.count", 1 do
          assert_difference "MonthlyProcessingRunStatement.count", 1 do
            assert_no_difference [ "Transaction.count", "Reconciliation.count", "StatementEntryResolution.count" ] do
              result = process
            end
          end
        end
      end
    end

    run = result.fetch(:run).reload
    assert_equal "blocked", run.status
    assert_equal Date.new(2026, 10, 1), run.month
    assert_equal result.fetch(:output_path), run.output_path
    assert_equal "staged", run.monthly_processing_run_statements.sole.staging_status
    assert_equal StatementImport.last, run.statement_imports.sole
  end

  test "exact rerun creates a new audit run and reuses the existing import" do
    first = process
    original_import_id = StatementImport.sole.id
    second = nil

    assert_no_difference [ "StatementImport.count", "StatementEntry.count", "Transaction.count" ] do
      assert_difference "MonthlyProcessingRun.count", 1 do
        second = process
      end
    end

    second_process = read_json(second, "process_run.json")
    assert_equal 0, second_process.fetch("staged_count")
    assert_equal 1, second_process.fetch("existing_count")
    assert_equal original_import_id, second.fetch(:run).statement_imports.sole.id
    assert_not_equal first.fetch(:output_path), second.fetch(:output_path)
  end

  test "ambiguous candidates and parser failures become explicit unresolved items" do
    2.times do |number|
      create(
        :transaction,
        account: @account,
        category: @category,
        occurred_on: Date.new(2026, 10, 5),
        description: "Candidate #{number}",
        amount_cents: -1_000
      )
    end
    ambiguous = process(dry_run: true)
    ambiguous_items = read_json(ambiguous, "unresolved_items.json").fetch("items")
    assert_includes ambiguous_items.pluck("type"), "ambiguous_match"

    @statement_path.binwrite("Date,Description,Amount\n2026-10-05,Broken,not-money\n")
    failed = process(dry_run: true, output_dir: @source_root.join("failed-output"))
    failed_items = read_json(failed, "unresolved_items.json").fetch("items")
    assert_includes failed_items.pluck("type"), "parser_failed"
    assert_equal 1, read_json(failed, "reconciliation_summary.json").fetch("total_failed_rows")
  end

  test "resolved exact reconciliation is reported ready but is not finalized" do
    process
    statement_import = StatementImport.sole
    entry = statement_import.statement_entries.sole
    create(
      :reconciliation,
      account: @account,
      starts_on: Date.new(2026, 9, 1),
      ends_on: Date.new(2026, 9, 30),
      statement_ending_balance_cents: 10_000,
      computed_ending_balance_cents: 10_000
    )
    transaction = create(
      :transaction,
      account: @account,
      category: @category,
      occurred_on: entry.posted_on,
      description: entry.normalized_description,
      amount_cents: entry.amount_cents
    )
    StatementEntries::MatchExisting.call(entry: entry, transaction: transaction)

    result = nil
    assert_no_difference "Reconciliation.count" do
      result = process(dry_run: true, output_dir: @source_root.join("ready-output"))
    end

    reconciliation = read_json(result, "reconciliation_summary.json")
    statement = read_json(result, "statements.json").fetch("statements").sole
    assert reconciliation.fetch("all_statements_ready")
    assert_equal 1, reconciliation.fetch("ready_count")
    assert statement.fetch("ready_to_finalize")
    assert_equal 0, statement.fetch("difference_cents")
    assert_nil transaction.reload.reconciliation_id
  end

  test "JSON is stable for identical inputs and contains cents only as integers" do
    output_one = @source_root.join("stable-one")
    output_two = @source_root.join("stable-two")
    first = process(dry_run: true, output_dir: output_one, clock: -> { FIXED_TIME })
    second = process(dry_run: true, output_dir: output_two, clock: -> { FIXED_TIME })

    MonthlyProcessing::OutputWriter::FILENAMES.grep(/\.json\z/).each do |filename|
      first_text = Pathname.new(first.fetch(:output_path)).join(filename).binread
      second_text = Pathname.new(second.fetch(:output_path)).join(filename).binread
      assert_equal first_text, second_text
      assert_cents_are_integers(JSON.parse(first_text))
    end
  end

  test "outputs and run directories have restrictive permissions and no database secrets" do
    result = process(dry_run: true)
    output_path = Pathname.new(result.fetch(:output_path))

    assert_equal 0o700, output_path.stat.mode & 0o777
    MonthlyProcessing::OutputWriter::FILENAMES.each do |filename|
      assert_equal 0o600, output_path.join(filename).stat.mode & 0o777
    end
    combined = MonthlyProcessing::OutputWriter::FILENAMES.map { |filename| output_path.join(filename).binread }.join
    assert_not_includes combined, "budget_app_test"
    assert_not_includes combined, "BUDGET_APP_DATABASE_PASSWORD"
    assert_not_includes combined, "postgres://"
  end

  test "unsafe output path inside the repository is rejected before any run is persisted" do
    assert_no_difference [ "MonthlyProcessingRun.count", "StatementImport.count" ] do
      assert_raises(MonthlyProcessing::PathSafety::UnsafePath) do
        process(dry_run: false, output_dir: Rails.root.join("tmp", "unsafe-monthly-output"))
      end
    end
  end

  test "apply failure preserves a failed audit run without partial statement rows" do
    @statement_path.binwrite("Description,Value\nBroken,10.00\n")

    assert_difference "MonthlyProcessingRun.count", 1 do
      assert_no_difference [ "StatementImport.count", "StatementEntry.count" ] do
        assert_raises(Statements::Parsers::GenericSignedCsv::FatalError) { process }
      end
    end

    run = MonthlyProcessingRun.last
    assert_equal "failed", run.status
    assert run.completed_at.present?
    assert_includes run.error_message, "FatalError"
    assert_empty run.statement_imports
  end

  private

  def process(dry_run: false, output_dir: nil, clock: -> { Time.current })
    MonthlyProcessing::ProcessMonth.call(
      month: "2026-10",
      source_dir: @source_root,
      output_dir: output_dir,
      dry_run: dry_run,
      clock: clock
    )
  end

  def read_json(result, filename)
    JSON.parse(Pathname.new(result.fetch(:output_path)).join(filename).binread)
  end

  def write_statement(amount:)
    @statement_path.binwrite("Date,Description,Amount\n2026-10-05,Groceries,#{amount}\n")
  end

  def write_manifest(ending_balance:)
    @source_root.join("manifest.yml").binwrite(<<~YAML)
      month: 2026-10
      statements:
        - account: primary-checking
          file: statements/checking.csv
          parser: generic_signed_csv
          starts_on: 2026-10-01
          ends_on: 2026-10-31
          ending_balance: "#{ending_balance}"
    YAML
  end

  def assert_cents_are_integers(value)
    case value
    when Hash
      value.each do |key, child|
        assert child.nil? || child.is_a?(Integer), "#{key} must contain integer cents" if key.end_with?("_cents")
        assert_cents_are_integers(child)
      end
    when Array
      value.each { |child| assert_cents_are_integers(child) }
    end
  end
end
