require "digest"
require "pathname"

module Statements
  class StageImport
    DEFAULT_FINANCE_ROOT = "/Users/ajs/Private/finance".freeze

    class Error < StandardError; end
    class UnknownAccount < Error; end
    class InvalidSource < Error; end

    def self.call(account:, file_path:, parser_key:, started_on: nil, ended_on: nil,
                  statement_ending_balance_cents: nil, dry_run: false, finance_root: nil)
      new(
        account: account,
        file_path: file_path,
        parser_key: parser_key,
        started_on: started_on,
        ended_on: ended_on,
        statement_ending_balance_cents: statement_ending_balance_cents,
        dry_run: dry_run,
        finance_root: finance_root
      ).call
    end

    def initialize(account:, file_path:, parser_key:, started_on:, ended_on:,
                   statement_ending_balance_cents:, dry_run:, finance_root:)
      @account_input = account
      @file_path = file_path
      @parser_key = parser_key
      @started_on = started_on
      @ended_on = ended_on
      @statement_ending_balance_cents = statement_ending_balance_cents
      @dry_run = dry_run
      @finance_root = finance_root.presence || ENV.fetch("BUDGET_FINANCE_ROOT", DEFAULT_FINANCE_ROOT)
    end

    def call
      account = resolve_account
      validate_period!
      source = resolve_source
      text = read_source(source.fetch(:real_path))
      file_sha256 = Digest::SHA256.hexdigest(text)
      parser_class = Statements::Parsers::Registry.fetch(@parser_key)
      parsed_rows = parser_class.new(text: text).parse
      rows = assign_source_identities(parsed_rows, account: account, file_sha256: file_sha256)
      existing = StatementImport.find_by(account: account, file_sha256: file_sha256)

      return build_result(account, source, parser_class, file_sha256, rows, existing: existing) if existing || @dry_run

      statement_import = persist_import(account, source, parser_class, file_sha256, rows)
      build_result(account, source, parser_class, file_sha256, rows, statement_import: statement_import)
    rescue ActiveRecord::RecordNotUnique
      existing = StatementImport.find_by!(account: account, file_sha256: file_sha256)
      build_result(account, source, parser_class, file_sha256, rows, existing: existing)
    end

    private

    def resolve_account
      account = if @account_input.is_a?(Account)
        @account_input
      else
        Account.find_by(import_key: @account_input.to_s)
      end

      unless account&.persisted? && account.import_key.present?
        raise UnknownAccount, "Unknown or unconfigured account import key: #{@account_input.inspect}"
      end

      account
    end

    def validate_period!
      return if @started_on.nil? || @ended_on.nil? || @started_on <= @ended_on

      raise Error, "Statement start date must not be after its end date"
    end

    def resolve_source
      root_path = Pathname.new(@finance_root.to_s).expand_path
      raise InvalidSource, "Finance root does not exist: #{root_path}" unless root_path.directory?

      supplied_path = Pathname.new(@file_path.to_s)
      if supplied_path.each_filename.include?("..")
        raise InvalidSource, "Statement path traversal is not allowed"
      end

      requested_path = supplied_path.expand_path
      raise InvalidSource, "Statement file does not exist: #{requested_path}" unless requested_path.file?

      real_root = root_path.realpath
      real_path = requested_path.realpath
      repository_root = Rails.root.realpath
      repository_prefix = "#{repository_root}#{File::SEPARATOR}"
      if real_root == repository_root || real_root.to_s.start_with?(repository_prefix)
        raise InvalidSource, "Finance root must be outside the application repository"
      end

      root_prefix = "#{real_root}#{File::SEPARATOR}"
      unless real_path.to_s.start_with?(root_prefix)
        raise InvalidSource, "Statement file must be contained within #{real_root}"
      end

      relative_path = requested_path.relative_path_from(root_path).cleanpath
      {
        real_path: real_path,
        source_filename: requested_path.basename.to_s,
        source_path: relative_path.to_s
      }
    rescue SystemCallError, ArgumentError => e
      raise InvalidSource, "Cannot read statement file: #{e.message}"
    end

    def assign_source_identities(rows, account:, file_sha256:)
      occurrences = Hash.new(0)
      rows.map do |row|
        base_key = Statements::SourceIdentity.base_key(row)
        occurrences[base_key] += 1
        row.merge(
          resolution_status: row[:status] == "parsed" ? "unresolved" : nil,
          source_identity: Statements::SourceIdentity.call(
            account_id: account.id,
            file_sha256: file_sha256,
            base_key: base_key,
            occurrence: occurrences.fetch(base_key)
          )
        )
      end
    end

    def read_source(real_path)
      File.binread(real_path)
    rescue SystemCallError => e
      raise InvalidSource, "Cannot read statement file: #{e.message}"
    end

    def persist_import(account, source, parser_class, file_sha256, rows)
      StatementImport.transaction do
        statement_import = StatementImport.create!(
          account: account,
          source_filename: source.fetch(:source_filename),
          source_path: source.fetch(:source_path),
          file_sha256: file_sha256,
          parser_key: parser_class::KEY,
          parser_version: parser_class::VERSION,
          started_on: @started_on,
          ended_on: @ended_on,
          statement_ending_balance_cents: @statement_ending_balance_cents,
          status: rows.any? { |row| row[:status] == "failed" } ? "failed" : "staged",
          row_count: rows.size,
          parsed_count: rows.count { |row| row[:status] == "parsed" },
          failed_count: rows.count { |row| row[:status] == "failed" }
        )
        rows.each { |row| statement_import.statement_entries.create!(row) }
        statement_import
      end
    end

    def build_result(account, source, parser_class, file_sha256, rows, statement_import: nil, existing: nil)
      parsed_rows = rows.select { |row| row[:status] == "parsed" }
      dates = parsed_rows.flat_map { |row| [ row[:posted_on], row[:transaction_on] ] }.compact
      amounts = parsed_rows.filter_map { |row| row[:amount_cents] }

      {
        statement_import_id: statement_import&.id || existing&.id,
        account_import_key: account.import_key,
        file: source.fetch(:source_path),
        file_sha256: file_sha256,
        parser_key: parser_class::KEY,
        parser_version: parser_class::VERSION,
        rows_seen: rows.size,
        rows_parsed: parsed_rows.size,
        rows_failed: rows.count { |row| row[:status] == "failed" },
        positive_total_cents: amounts.select(&:positive?).sum,
        negative_total_cents: amounts.select(&:negative?).sum,
        detected_start_date: dates.min,
        detected_end_date: dates.max,
        status: result_status(rows, statement_import: statement_import, existing: existing),
        exact_rerun: existing.present?,
        errors: rows.filter_map do |row|
          next unless row[:status] == "failed"

          {
            source_row_number: row[:source_row_number],
            error_code: row[:error_code],
            error_message: row[:error_message]
          }
        end
      }
    end

    def result_status(rows, statement_import:, existing:)
      return "exact_rerun" if existing
      return rows.any? { |row| row[:status] == "failed" } ? "dry_run_failed" : "dry_run_staged" if @dry_run

      statement_import.status
    end
  end
end
