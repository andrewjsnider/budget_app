require "json"

module MonthlyProcessing
  class BundleBuilder
    SCHEMA_VERSION = Manifest::SCHEMA_VERSION

    def self.call(month:, run_id:, status:, dry_run:, input_digest:, source_root:, generated_at:,
                  policy_versions:, processed_statements:, staged_count:, existing_count:, warnings:)
      new(
        month: month,
        run_id: run_id,
        status: status,
        dry_run: dry_run,
        input_digest: input_digest,
        source_root: source_root,
        generated_at: generated_at,
        policy_versions: policy_versions,
        processed_statements: processed_statements,
        staged_count: staged_count,
        existing_count: existing_count,
        warnings: warnings
      ).call
    end

    def initialize(month:, run_id:, status:, dry_run:, input_digest:, source_root:, generated_at:,
                   policy_versions:, processed_statements:, staged_count:, existing_count:, warnings:)
      @month = month
      @run_id = run_id
      @status = status
      @dry_run = dry_run
      @input_digest = input_digest
      @source_root = source_root
      @generated_at = generated_at
      @policy_versions = policy_versions
      @processed_statements = processed_statements
      @staged_count = staged_count
      @existing_count = existing_count
      @warnings = warnings
    end

    def call
      summaries = @processed_statements.map { |item| item.fetch(:summary) }
      unresolved = build_unresolved_items
      reconciliation = reconciliation_summary(summaries)
      files = {
        "process_run.json" => json(base_metadata.merge(process_run_payload(summaries))),
        "statements.json" => json(base_metadata.merge(statements: summaries)),
        "unresolved_items.json" => json(base_metadata.merge(items: unresolved)),
        "reconciliation_summary.json" => json(base_metadata.merge(reconciliation)),
        "reconciliation_summary.md" => markdown_summary(summaries, reconciliation)
      }

      {
        files: files,
        process_run: base_metadata.merge(process_run_payload(summaries)),
        statements: summaries,
        unresolved_items: unresolved,
        reconciliation_summary: base_metadata.merge(reconciliation)
      }
    end

    private

    def base_metadata
      {
        schema_version: SCHEMA_VERSION,
        month: @month.strftime("%Y-%m"),
        run_id: @run_id,
        generated_at: @generated_at.iso8601(6),
        dry_run: @dry_run,
        input_digest: @input_digest,
        policy_versions: @policy_versions
      }
    end

    def process_run_payload(summaries)
      {
        status: @status,
        source_root: @source_root.to_s,
        statement_count: summaries.size,
        staged_count: @staged_count,
        existing_count: @existing_count,
        failed_count: summaries.count { |statement| statement.fetch(:failed_count).positive? },
        blocked_count: summaries.count { |statement| !statement.fetch(:ready_to_finalize) },
        warnings: @warnings
      }
    end

    def build_unresolved_items
      items = @processed_statements.flat_map do |processed|
        summary = processed.fetch(:summary)
        review = processed.fetch(:review)
        entry_items = review.fetch(:failed_entries).map do |entry|
          entry_item("parser_failed", summary, entry)
        end
        entry_items.concat(review.fetch(:entries).filter_map do |entry|
          next unless %w[unresolved ambiguous].include?(entry.fetch(:resolution_status))

          type = if entry.fetch(:resolution_status) == "ambiguous" || entry.dig(:evidence, :classification) == "ambiguous"
            "ambiguous_match"
          elsif entry.dig(:evidence, :classification) == "no_candidate"
            "unresolved_no_candidate"
          else
            "unresolved_match"
          end
          entry_item(type, summary, entry)
        end)
        entry_items.concat(statement_blocker_items(summary))
      end

      items.sort_by do |item|
        [
          item.fetch(:account_import_key),
          item.fetch(:source_path),
          item.fetch(:source_row_number, 0).to_i,
          item.fetch(:type)
        ]
      end
    end

    def entry_item(type, summary, entry)
      {
        type: type,
        entry_id: entry.fetch(:entry_id),
        statement_import_id: summary.fetch(:statement_import_id),
        account_import_key: summary.fetch(:account_import_key),
        source_path: summary.fetch(:source_path),
        source_row_number: entry.fetch(:source_row_number),
        date: entry.fetch(:date)&.iso8601,
        description: entry.fetch(:description),
        amount_cents: entry.fetch(:amount_cents),
        resolution_status: entry.fetch(:resolution_status),
        recommended_action: entry.fetch(:recommended_action),
        candidate_transactions: entry.fetch(:candidate_transactions),
        evidence: entry.fetch(:evidence),
        error_code: entry.fetch(:error_code),
        error_message: entry.fetch(:error_message)
      }
    end

    def statement_blocker_items(summary)
      aggregate_entry_codes = %w[failed_entries unresolved_entries ambiguous_entries]
      summary.fetch(:blockers).filter_map do |blocker|
        next if aggregate_entry_codes.include?(blocker.fetch(:code))

        {
          type: blocker_type(blocker.fetch(:code)),
          statement_import_id: summary.fetch(:statement_import_id),
          account_import_key: summary.fetch(:account_import_key),
          source_path: summary.fetch(:source_path),
          blocker: blocker
        }
      end
    end

    def blocker_type(code)
      {
        "overlapping_finalized_reconciliation" => "overlapping_statement_period"
      }.fetch(code, code)
    end

    def reconciliation_summary(summaries)
      ready_count = summaries.count { |statement| statement.fetch(:ready_to_finalize) }
      {
        all_statements_ready: ready_count == summaries.size,
        ready_count: ready_count,
        blocked_count: summaries.size - ready_count,
        total_unresolved: summaries.sum { |statement| statement.fetch(:unresolved_count) },
        total_ambiguous: summaries.sum { |statement| statement.fetch(:ambiguous_count) },
        total_failed_rows: summaries.sum { |statement| statement.fetch(:failed_count) },
        statements: summaries.map do |statement|
          statement.slice(
            :statement_import_id,
            :account_import_key,
            :source_path,
            :opening_balance_cents,
            :activity_cents,
            :statement_ending_balance_cents,
            :computed_ending_balance_cents,
            :difference_cents,
            :ready_to_finalize,
            :blockers
          )
        end
      }
    end

    def markdown_summary(summaries, reconciliation)
      lines = [ "# #{@month.strftime('%B %Y')} Financial Processing", "" ]
      summaries.each do |statement|
        lines.concat(
          [
            "## #{statement.fetch(:account_import_key).split('-').map(&:capitalize).join(' ')}",
            "",
            "Statement: `#{statement.fetch(:source_path)}`",
            "Statement rows: #{statement.fetch(:row_count)}",
            "Matched: #{statement.fetch(:matched_count)}",
            "New transactions: #{statement.fetch(:new_transaction_count)}",
            "Unresolved: #{statement.fetch(:unresolved_count)}",
            "Ambiguous: #{statement.fetch(:ambiguous_count)}",
            "Failed rows: #{statement.fetch(:failed_count)}",
            "Ignored: #{statement.fetch(:ignored_count)}",
            "",
            "Statement ending balance: #{format_money(statement.fetch(:statement_ending_balance_cents))}",
            "Computed ending balance: #{format_money(statement.fetch(:computed_ending_balance_cents))}",
            "Difference: #{format_money(statement.fetch(:difference_cents))}",
            "Ready to finalize: #{statement.fetch(:ready_to_finalize) ? 'Yes' : 'No'}",
            "",
            "Blockers:"
          ]
        )
        blockers = statement.fetch(:blockers)
        lines << "- None" if blockers.empty?
        blockers.each { |blocker| lines << "- #{blocker.fetch(:message)}" }
        lines << ""
      end
      lines.concat(
        [
          "## Month Summary",
          "",
          "Statements ready: #{reconciliation.fetch(:ready_count)} of #{summaries.size}",
          "Unresolved entries: #{reconciliation.fetch(:total_unresolved)}",
          "Ambiguous entries: #{reconciliation.fetch(:total_ambiguous)}",
          "Failed parser rows: #{reconciliation.fetch(:total_failed_rows)}",
          "All statements ready: #{reconciliation.fetch(:all_statements_ready) ? 'Yes' : 'No'}",
          ""
        ]
      )
      lines.join("\n")
    end

    def format_money(cents)
      return "pending" if cents.nil?

      sign = cents.negative? ? "-" : ""
      dollars, remainder = cents.abs.divmod(100)
      grouped = dollars.to_s.reverse.scan(/.{1,3}/).join(",").reverse
      "#{sign}$#{grouped}.#{format('%02d', remainder)}"
    end

    def json(value)
      "#{JSON.pretty_generate(value)}\n"
    end
  end
end
