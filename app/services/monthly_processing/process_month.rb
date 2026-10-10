module MonthlyProcessing
  class ProcessMonth
    DEFAULT_FINANCE_ROOT = "/Users/ajs/Private/finance".freeze

    class ExistingImportMismatch < StandardError; end

    def self.call(month:, source_dir: nil, output_dir: nil, dry_run: false, clock: -> { Time.current })
      new(
        month: month,
        source_dir: source_dir,
        output_dir: output_dir,
        dry_run: dry_run,
        clock: clock
      ).call
    end

    def initialize(month:, source_dir:, output_dir:, dry_run:, clock:)
      @month_key = month.to_s
      @source_dir = source_dir.presence || File.join(
        ENV.fetch("BUDGET_FINANCE_ROOT", DEFAULT_FINANCE_ROOT),
        @month_key
      )
      @output_dir = output_dir
      @dry_run = dry_run
      @clock = clock
      @run = nil
    end

    def call
      manifest = Manifest.call(month: @month_key, source_dir: @source_dir)
      output_root = PathSafety.output_root(@output_dir.presence || manifest.source_root.join("output"))
      started_at = @clock.call
      @run = create_run(manifest, started_at) unless @dry_run
      processed, staged_count, existing_count = process_statements(manifest)
      status = processed.all? { |item| item.dig(:summary, :ready_to_finalize) } ? "completed" : "blocked"
      generated_at = @clock.call
      run_name = build_run_name(generated_at, manifest.input_digest)
      expected_output_path = output_root.join("runs", run_name)
      @run&.update!(output_path: expected_output_path.to_s)
      warnings = build_warnings(processed)
      bundle = BundleBuilder.call(
        month: manifest.month,
        run_id: @run&.id,
        status: status,
        dry_run: @dry_run,
        input_digest: manifest.input_digest,
        source_root: manifest.source_root,
        generated_at: generated_at,
        policy_versions: manifest.policy_versions,
        processed_statements: processed,
        staged_count: staged_count,
        existing_count: existing_count,
        warnings: warnings
      )
      output_path = OutputWriter.call(
        output_root: output_root,
        run_name: run_name,
        files: bundle.fetch(:files)
      )
      complete_run!(status, output_path, generated_at)

      bundle.merge(output_path: output_path.to_s, run: @run)
    rescue StandardError => e
      fail_run!(e)
      raise
    end

    private

    def create_run(manifest, started_at)
      MonthlyProcessingRun.create!(
        month: manifest.month,
        status: "running",
        started_at: started_at,
        dry_run: false,
        input_digest: manifest.input_digest,
        policy_version: Manifest::SCHEMA_VERSION,
        source_root: manifest.source_root.to_s
      )
    end

    def process_statements(manifest)
      staged_count = 0
      existing_count = 0
      processed = manifest.statements.map.with_index do |definition, position|
        existing = StatementImport.find_by(
          account_id: definition.account.id,
          file_sha256: definition.file_sha256
        )
        validate_existing_import!(existing, definition) if existing

        if existing
          existing_count += 1
          statement_import = existing
          entries = nil
          staging_status = "existing"
        elsif @dry_run
          staged_count += 1
          preview = StatementPreview.call(definition: definition)
          statement_import = preview.statement_import
          entries = preview.entries
          staging_status = "staged"
        else
          stage_result = Statements::StageImport.call(
            account: definition.account,
            file_path: definition.file_path,
            parser_key: definition.parser_key,
            started_on: definition.started_on,
            ended_on: definition.ended_on,
            statement_ending_balance_cents: definition.statement_ending_balance_cents,
            dry_run: false,
            finance_root: manifest.source_root
          )
          statement_import = StatementImport.find(stage_result.fetch(:statement_import_id))
          entries = nil
          staging_status = stage_result.fetch(:exact_rerun) ? "existing" : "staged"
          stage_result.fetch(:exact_rerun) ? existing_count += 1 : staged_count += 1
        end

        attach_statement(statement_import, position, staging_status) if @run
        review = Statements::ReviewImport.call(statement_import: statement_import, entries: entries)
        {
          summary: statement_summary(definition, statement_import, review),
          review: review,
          staging_status: staging_status
        }
      end
      [ processed, staged_count, existing_count ]
    end

    def validate_existing_import!(statement_import, definition)
      expected = {
        parser_key: definition.parser_key,
        parser_version: definition.parser_version,
        started_on: definition.started_on,
        ended_on: definition.ended_on,
        statement_ending_balance_cents: definition.statement_ending_balance_cents
      }
      mismatches = expected.filter_map do |attribute, value|
        attribute if statement_import.public_send(attribute) != value
      end
      return if mismatches.empty?

      raise ExistingImportMismatch,
        "Existing statement import #{statement_import.id} conflicts with manifest fields: #{mismatches.join(', ')}"
    end

    def attach_statement(statement_import, position, staging_status)
      @run.monthly_processing_run_statements.create!(
        statement_import: statement_import,
        position: position,
        staging_status: staging_status
      )
    end

    def statement_summary(definition, statement_import, review)
      entries = review.fetch(:entries)
      {
        statement_import_id: statement_import.id,
        account_import_key: definition.account_import_key,
        source_path: definition.source_path,
        file_sha256: definition.file_sha256,
        parser_key: definition.parser_key,
        parser_version: definition.parser_version,
        started_on: definition.started_on.iso8601,
        ended_on: definition.ended_on.iso8601,
        statement_ending_balance_cents: definition.statement_ending_balance_cents,
        parse_status: review.fetch(:failed).positive? ? "failed" : "parsed",
        row_count: review.fetch(:rows),
        parsed_count: review.fetch(:rows) - review.fetch(:failed),
        failed_count: review.fetch(:failed),
        matched_count: entries.count { |entry| entry.fetch(:resolution_status) == "matched" },
        new_transaction_count: entries.count { |entry| entry.fetch(:resolution_status) == "new_transaction" },
        unresolved_count: review.fetch(:unmatched),
        ambiguous_count: review.fetch(:ambiguous),
        ignored_count: review.fetch(:ignored),
        opening_balance_cents: review.fetch(:opening_balance_cents),
        activity_cents: review.fetch(:activity_cents),
        computed_ending_balance_cents: review.fetch(:computed_ending_balance_cents),
        difference_cents: review.fetch(:difference_cents),
        ready_to_finalize: review.fetch(:ready_to_finalize),
        blockers: review.fetch(:blockers)
      }
    end

    def build_run_name(generated_at, input_digest)
      return format("run-%08d", @run.id) if @run

      timestamp = generated_at.utc.strftime("%Y%m%d%H%M%S%6N")
      "dry-run-#{timestamp}-#{input_digest.first(8)}"
    end

    def build_warnings(processed)
      warnings = []
      if @dry_run && processed.any? { |item| item.fetch(:staging_status) == "staged" }
        warnings << "Dry run previewed unstaged statements; entry and import IDs are null until apply mode."
      end
      warnings
    end

    def complete_run!(status, output_path, completed_at)
      return unless @run

      @run.update!(
        status: status,
        output_path: output_path.to_s,
        completed_at: completed_at,
        error_message: nil
      )
    end

    def fail_run!(error)
      return unless @run&.persisted?
      return if @run.terminal?

      @run.update_columns(
        status: "failed",
        completed_at: @clock.call,
        error_message: "#{error.class}: #{error.message}".truncate(2000),
        updated_at: @clock.call
      )
    rescue StandardError
      nil
    end
  end
end
