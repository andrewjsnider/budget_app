require "csv"
require "digest"

module Transactions
  class HistoricalImport
    POLICY_VERSION = "historical-import-v1"
    DATE_HEADERS = [ "posting date", "date", "transaction date", "posted date" ].freeze
    AMOUNT_HEADERS = [ "amount" ].freeze
    DESCRIPTION_HEADERS = [ "description", "merchant", "payee" ].freeze
    MATCH_WINDOW_DAYS = 3

    class InvalidSource < StandardError; end

    def self.call(file_path:, account:, after:, dry_run:)
      new(file_path:, account:, after:, dry_run:).call
    end

    def initialize(file_path:, account:, after:, dry_run:)
      @file_path = MonthlyProcessing::PathSafety.source_file(file_path)
      @account = account
      @after = after
      @dry_run = dry_run
      @file_digest = Digest::SHA256.file(@file_path).hexdigest
    end

    def call
      rows = parse_rows
      summary = base_summary

      rows.each do |parsed|
        summary[:total_source_rows] += 1
        process_row(parsed, summary)
      end

      summary[:clear_new_count] = @clear_new_count || 0
      summary[:created_count] = @created_count || 0
      summary[:matched_existing_count] = summary[:already_present_count] + summary[:definite_match_count]
      summary[:ambiguous_skipped_count] = summary[:ambiguous_count]
      summary[:failed_count] = summary[:malformed_count]
      summary[:manual_review_required] = summary[:ambiguous_count].positive? || summary[:malformed_count].positive?
      summary[:eligible] = summary[:eligible_rows]
      summary[:created] = summary[:created_count]
      summary[:matched_existing] = summary[:matched_existing_count]
      summary[:ambiguous_skipped] = summary[:ambiguous_skipped_count]
      summary[:failed] = summary[:failed_count]
      summary[:status] = :ok
      summary
    end

    private

    def base_summary
      {
        schema_version: POLICY_VERSION,
        file: @file_path.to_s,
        file_sha256: @file_digest,
        account_import_key: @account.import_key,
        after: @after.iso8601,
        dry_run: @dry_run,
        total_source_rows: 0,
        rows_at_or_before_cutoff: 0,
        eligible_rows: 0,
        already_present_count: 0,
        definite_match_count: 0,
        ambiguous_count: 0,
        clear_new_count: 0,
        created_count: 0,
        matched_existing_count: 0,
        ambiguous_skipped_count: 0,
        failed_count: 0,
        manual_review_required: false,
        eligible: 0,
        created: 0,
        matched_existing: 0,
        ambiguous_skipped: 0,
        failed: 0,
        malformed_count: 0,
        ambiguous_rows: [],
        malformed_rows: []
      }
    end

    def parse_rows
      text = File.binread(@file_path)
        .sub(/\A\xEF\xBB\xBF/, "")
        .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
      rows = CSV.parse(text, headers: true, liberal_parsing: true)
      headers = rows.headers&.compact&.map(&:to_s)
      raise InvalidSource, "CSV has no headers" if headers.blank?
      missing = [ DATE_HEADERS, AMOUNT_HEADERS, DESCRIPTION_HEADERS ].each_with_index.filter_map do |choices, index|
        next if header_for(headers, choices)

        %w[date amount description][index]
      end
      raise InvalidSource, "CSV is missing required #{missing.join(', ')} column(s)" if missing.any?

      rows.each_with_index.map { |row, index| ParsedRow.new(index + 2, row, headers) }
    rescue CSV::MalformedCSVError => e
      raise InvalidSource, "Malformed CSV: #{e.message}"
    end

    def process_row(parsed, summary)
      date = parse_date(value_for(parsed, DATE_HEADERS))
      description = normalize_description(value_for(parsed, DESCRIPTION_HEADERS))
      amount_cents = parse_amount(value_for(parsed, AMOUNT_HEADERS))

      if date.nil? || description.blank? || amount_cents.nil? || amount_cents.zero?
        add_malformed(summary, parsed, date:, description:, amount_cents:,
          error_code: malformed_code(date, description, amount_cents))
        return
      end

      if date <= @after
        summary[:rows_at_or_before_cutoff] += 1
        return
      end

      summary[:eligible_rows] += 1
      provenance = provenance_for(parsed.source_row_number)
      if (existing = Transaction.find_by(account_id: @account.id, import_hash: provenance))
        summary[:already_present_count] += 1
        return
      end

      candidates = candidates_for(date, description, amount_cents)
      if candidates.length == 1 && strict_candidate?(candidates.first, date, description)
        summary[:definite_match_count] += 1
        return
      end

      if candidates.any?
        summary[:ambiguous_count] += 1
        summary[:ambiguous_rows] << ambiguous_row(parsed, date, description, amount_cents, candidates)
        return
      end

      @clear_new_count = (@clear_new_count || 0) + 1
      return if @dry_run

      create_transaction!(parsed, date, description, amount_cents, provenance, summary)
    end

    def create_transaction!(parsed, date, description, amount_cents, provenance, summary)
      created = Transaction.transaction do
        category = StatementEntries::CategoryResolver.call(
          description: description,
          amount_cents: amount_cents
        ).category
        Transaction.create!(
          account: @account,
          occurred_on: date,
          description: description,
          amount_cents: amount_cents,
          category: category,
          cleared: true,
          import_hash: provenance
        )
      end
      @created_count = (@created_count || 0) + 1
      created
    rescue ActiveRecord::RecordNotUnique
      # A concurrent or prior run won the provenance race. It is safe to
      # treat this row as already present without touching that transaction.
      summary[:already_present_count] += 1
      @clear_new_count -= 1
    rescue ActiveRecord::RecordInvalid => e
      add_malformed(
        summary,
        parsed,
        date: date,
        description: description,
        amount_cents: amount_cents,
        error_code: "creation_failed",
        error_message: e.record.errors.full_messages.to_sentence
      )
      @clear_new_count -= 1
    end

    def candidates_for(date, description, amount_cents)
      Transaction.where(account_id: @account.id, amount_cents: amount_cents)
        .where(occurred_on: (date - MATCH_WINDOW_DAYS)..(date + MATCH_WINDOW_DAYS))
        .where(starting_balance: false)
        .order(:occurred_on, :id)
    end

    def strict_candidate?(transaction, date, description)
      transaction.occurred_on == date ||
        StatementEntries::DescriptionNormalizer.match?(transaction.description, description)
    end

    def ambiguous_row(parsed, date, description, amount_cents, candidates)
      {
        source_row_number: parsed.source_row_number,
        date: date.iso8601,
        description: description,
        signed_amount_cents: amount_cents,
        candidate_transactions: candidates.map do |transaction|
          candidate_date_delta = (transaction.occurred_on - date).to_i
          {
            id: transaction.id,
            date: transaction.occurred_on.iso8601,
            description: transaction.description,
            signed_amount_cents: transaction.amount_cents,
            evidence: {
              same_account: transaction.account_id == @account.id,
              amount_exact: transaction.amount_cents == amount_cents,
              date_delta_days: candidate_date_delta,
              date_exact: candidate_date_delta.zero?,
              description_exact: StatementEntries::DescriptionNormalizer.exact?(transaction.description, description),
              description_normalized_match: StatementEntries::DescriptionNormalizer.match?(transaction.description, description),
              reconciled: transaction.reconciled_at.present? || transaction.reconciliation_id.present?,
              policy_version: POLICY_VERSION
            }
          }
        end
      }
    end

    def add_malformed(summary, parsed, date:, description:, amount_cents:, error_code:, error_message: nil)
      summary[:malformed_count] += 1
      summary[:malformed_rows] << {
        source_row_number: parsed.source_row_number,
        date: date&.iso8601,
        description: description.presence,
        signed_amount_cents: amount_cents,
        error_code: error_code,
        error_message: error_message || error_code
      }
    end

    def malformed_code(date, description, amount_cents)
      return "invalid_date" unless date
      return "missing_description" if description.blank?
      return "invalid_amount" if amount_cents.nil?
      return "zero_amount" if amount_cents.zero?

      "invalid_row"
    end

    def parse_date(value)
      raw = value.to_s.strip
      return nil if raw.blank?

      Date.strptime(raw, "%m/%d/%Y")
    rescue ArgumentError, Date::Error
      begin
        Date.parse(raw)
      rescue ArgumentError, Date::Error
        nil
      end
    end

    def parse_amount(value)
      Statements::DecimalCents.call(value)
    rescue Statements::DecimalCents::InvalidAmount
      nil
    end

    def normalize_description(value)
      value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
        .gsub(/\s+/, " ").strip[0, 255]
    end

    def value_for(parsed, choices)
      header = header_for(parsed.headers, choices)
      header && parsed.row[header]
    end

    def header_for(headers, choices)
      choices.each do |choice|
        normalized_choice = normalize_header(choice)
        return headers.find { |header| normalize_header(header) == normalized_choice }
      end
      nil
    end

    def normalize_header(header)
      header.to_s.downcase.strip.gsub(/\s+/, " ")
    end

    def provenance_for(source_row_number)
      Digest::SHA256.hexdigest(
        [ POLICY_VERSION, @account.id, @file_digest, source_row_number ].join("|")
      )
    end

    ParsedRow = Data.define(:source_row_number, :row, :headers)
  end
end
