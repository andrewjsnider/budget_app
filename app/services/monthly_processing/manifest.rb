require "date"
require "digest"
require "json"
require "yaml"

module MonthlyProcessing
  class Manifest
    SCHEMA_VERSION = "monthly-processing-v1".freeze
    MANIFEST_FILENAME = "manifest.yml".freeze
    TOP_LEVEL_KEYS = %w[month statements].freeze
    STATEMENT_KEYS = %w[account file parser starts_on ends_on ending_balance].freeze

    Statement = Data.define(
      :account,
      :account_import_key,
      :source_path,
      :file_path,
      :file_sha256,
      :parser_key,
      :parser_version,
      :started_on,
      :ended_on,
      :statement_ending_balance_cents
    )
    Result = Data.define(:month, :month_key, :source_root, :statements, :input_digest, :policy_versions)

    class InvalidManifest < StandardError; end

    def self.call(month:, source_dir:)
      new(month: month, source_dir: source_dir).call
    end

    def initialize(month:, source_dir:)
      @month_key = month.to_s
      @source_dir = source_dir
    end

    def call
      month = parse_month(@month_key)
      source_root = PathSafety.source_root(@source_dir)
      manifest_path = PathSafety.contained_file(
        root: source_root,
        relative_path: MANIFEST_FILENAME,
        label: "Monthly manifest"
      )
      document = load_yaml(manifest_path)
      validate_keys!(document, TOP_LEVEL_KEYS, "manifest")
      manifest_month = document.fetch("month").to_s
      unless manifest_month == @month_key
        raise InvalidManifest, "Manifest month #{manifest_month.inspect} does not match #{@month_key}"
      end

      statement_rows = document.fetch("statements")
      raise InvalidManifest, "Manifest statements must be a nonempty array" unless statement_rows.is_a?(Array) && statement_rows.any?

      statements = statement_rows.map.with_index do |row, index|
        build_statement(row, index: index, source_root: source_root)
      end.sort_by { |statement| [ statement.account_import_key, statement.source_path ] }
      reject_duplicates!(statements)
      policy_versions = build_policy_versions(statements)
      input_digest = build_input_digest(month, statements, policy_versions)

      Result.new(
        month: month,
        month_key: @month_key,
        source_root: source_root,
        statements: statements,
        input_digest: input_digest,
        policy_versions: policy_versions
      )
    rescue KeyError => e
      raise InvalidManifest, "Manifest is missing required field: #{e.key}"
    rescue Psych::Exception => e
      raise InvalidManifest, "Manifest YAML is invalid: #{e.message}"
    end

    private

    def parse_month(value)
      unless value.match?(/\A\d{4}-\d{2}\z/)
        raise InvalidManifest, "MONTH must use YYYY-MM"
      end

      parsed = Date.strptime(value, "%Y-%m")
      raise InvalidManifest, "MONTH must use YYYY-MM" unless parsed.strftime("%Y-%m") == value

      parsed.beginning_of_month
    rescue Date::Error
      raise InvalidManifest, "MONTH must use YYYY-MM"
    end

    def load_yaml(path)
      document = YAML.safe_load(File.binread(path), permitted_classes: [ Date ], aliases: false)
      raise InvalidManifest, "Manifest must contain a mapping" unless document.is_a?(Hash)

      document.transform_keys(&:to_s)
    end

    def build_statement(raw_row, index:, source_root:)
      raise InvalidManifest, "Statement #{index + 1} must be a mapping" unless raw_row.is_a?(Hash)

      row = raw_row.transform_keys(&:to_s)
      validate_keys!(row, STATEMENT_KEYS, "statement #{index + 1}")
      account_key = required_string(row, "account", index)
      account = Account.find_by(import_key: account_key, archived: false)
      raise InvalidManifest, "Unknown active account import key: #{account_key}" unless account

      parser_key = required_string(row, "parser", index)
      parser_class = Statements::Parsers::Registry.fetch(parser_key)
      source_path = required_string(row, "file", index)
      file_path = PathSafety.contained_file(root: source_root, relative_path: source_path)
      started_on = parse_date(row.fetch("starts_on"), "starts_on", index)
      ended_on = parse_date(row.fetch("ends_on"), "ends_on", index)
      if started_on > ended_on
        raise InvalidManifest, "Statement #{index + 1} starts_on must not be after ends_on"
      end
      ending_balance = Statements::DecimalCents.call(row.fetch("ending_balance"))

      Statement.new(
        account: account,
        account_import_key: account_key,
        source_path: Pathname.new(source_path).cleanpath.to_s,
        file_path: file_path,
        file_sha256: Digest::SHA256.file(file_path).hexdigest,
        parser_key: parser_class::KEY,
        parser_version: parser_class::VERSION,
        started_on: started_on,
        ended_on: ended_on,
        statement_ending_balance_cents: ending_balance
      )
    rescue Statements::DecimalCents::InvalidAmount => e
      raise InvalidManifest, "Statement #{index + 1} ending_balance #{e.message}"
    rescue Statements::Parsers::UnknownParser => e
      raise InvalidManifest, e.message
    end

    def validate_keys!(hash, allowed, label)
      unknown = hash.keys.map(&:to_s) - allowed
      missing = allowed - hash.keys.map(&:to_s)
      raise InvalidManifest, "Unknown #{label} fields: #{unknown.join(', ')}" if unknown.any?
      raise InvalidManifest, "Missing #{label} fields: #{missing.join(', ')}" if missing.any?
    end

    def required_string(row, key, index)
      value = row.fetch(key).to_s.strip
      raise InvalidManifest, "Statement #{index + 1} #{key} is required" if value.blank?

      value
    end

    def parse_date(value, field, index)
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue Date::Error
      raise InvalidManifest, "Statement #{index + 1} #{field} must use YYYY-MM-DD"
    end

    def reject_duplicates!(statements)
      duplicates = statements.group_by { |statement| [ statement.account.id, statement.file_path.to_s ] }
        .select { |_key, rows| rows.many? }
      if duplicates.any?
        raise InvalidManifest, "Manifest contains duplicate statement definitions for the same account and file"
      end

      duplicate_content = statements.group_by { |statement| [ statement.account.id, statement.file_sha256 ] }
        .select { |_key, rows| rows.many? }
      return if duplicate_content.empty?

      raise InvalidManifest, "Manifest contains duplicate statement content for the same account"
    end

    def build_policy_versions(statements)
      parser_versions = statements.each_with_object({}) do |statement, result|
        result[statement.parser_key] = statement.parser_version
      end.sort.to_h
      {
        statement_parser: parser_versions,
        statement_match: StatementEntries::Matcher::POLICY_VERSION,
        monthly_processing: SCHEMA_VERSION
      }
    end

    def build_input_digest(month, statements, policy_versions)
      canonical = {
        schema_version: SCHEMA_VERSION,
        month: month.strftime("%Y-%m"),
        policy_versions: policy_versions,
        statements: statements.map do |statement|
          {
            account: statement.account_import_key,
            file: statement.source_path,
            file_sha256: statement.file_sha256,
            parser: statement.parser_key,
            parser_version: statement.parser_version,
            starts_on: statement.started_on.iso8601,
            ends_on: statement.ended_on.iso8601,
            statement_ending_balance_cents: statement.statement_ending_balance_cents
          }
        end
      }
      Digest::SHA256.hexdigest(JSON.generate(canonical))
    end
  end
end
