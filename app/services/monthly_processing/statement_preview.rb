module MonthlyProcessing
  class StatementPreview
    Result = Data.define(:statement_import, :entries)

    def self.call(definition:)
      new(definition: definition).call
    end

    def initialize(definition:)
      @definition = definition
    end

    def call
      parser_class = Statements::Parsers::Registry.fetch(@definition.parser_key)
      parsed_rows = parser_class.new(text: File.binread(@definition.file_path)).parse
      rows = assign_source_identities(parsed_rows)
      statement_import = StatementImport.new(
        account: @definition.account,
        source_filename: @definition.file_path.basename.to_s,
        source_path: @definition.source_path,
        file_sha256: @definition.file_sha256,
        parser_key: @definition.parser_key,
        parser_version: @definition.parser_version,
        started_on: @definition.started_on,
        ended_on: @definition.ended_on,
        statement_ending_balance_cents: @definition.statement_ending_balance_cents,
        status: rows.any? { |row| row.fetch(:status) == "failed" } ? "failed" : "staged",
        row_count: rows.size,
        parsed_count: rows.count { |row| row.fetch(:status) == "parsed" },
        failed_count: rows.count { |row| row.fetch(:status) == "failed" }
      )
      entries = rows.map do |row|
        StatementEntry.new(row).tap { |entry| entry.statement_import = statement_import }
      end

      Result.new(statement_import: statement_import, entries: entries)
    end

    private

    def assign_source_identities(rows)
      occurrences = Hash.new(0)
      rows.map do |row|
        base_key = Statements::SourceIdentity.base_key(row)
        occurrences[base_key] += 1
        row.merge(
          resolution_status: row.fetch(:status) == "parsed" ? "unresolved" : nil,
          source_identity: Statements::SourceIdentity.call(
            account_id: @definition.account.id,
            file_sha256: @definition.file_sha256,
            base_key: base_key,
            occurrence: occurrences.fetch(base_key)
          )
        )
      end
    end
  end
end
