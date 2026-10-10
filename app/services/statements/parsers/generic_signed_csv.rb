require "csv"

module Statements
  module Parsers
    class GenericSignedCsv
      KEY = "generic_signed_csv".freeze
      VERSION = "1".freeze

      class FatalError < StandardError; end

      POSTED_DATE_HEADERS = [ "posting date", "posted date", "date" ].freeze
      TRANSACTION_DATE_HEADERS = [ "transaction date" ].freeze
      DESCRIPTION_HEADERS = [ "description", "merchant", "payee" ].freeze
      AMOUNT_HEADERS = [ "amount" ].freeze
      TRANSACTION_ID_HEADERS = [ "transaction id", "transaction_id", "reference number", "reference" ].freeze
      DATE_FORMATS = [ "%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y" ].freeze

      def initialize(text:)
        @text = text.to_s.sub(/\A\xEF\xBB\xBF/, "")
      end

      def parse
        table = CSV.parse(
          @text,
          headers: true,
          col_sep: detect_column_separator,
          liberal_parsing: true,
          skip_blanks: false
        )
        headers = table.headers&.map { |header| header&.to_s }
        validate_headers!(headers)

        table.each_with_index.map do |row, index|
          parse_row(row, source_row_number: index + 2)
        end
      rescue CSV::MalformedCSVError, EncodingError => e
        raise FatalError, "Malformed statement file: #{e.message}"
      end

      private

      def detect_column_separator
        header_line = @text.lines.first.to_s
        header_line.count("\t") > header_line.count(",") ? "\t" : ","
      end

      def validate_headers!(headers)
        raise FatalError, "Statement CSV has no headers" if headers.blank?

        normalized = headers.compact.map { |header| normalize_header(header) }
        has_date = (POSTED_DATE_HEADERS + TRANSACTION_DATE_HEADERS).any? { |name| normalized.include?(name) }
        has_amount = AMOUNT_HEADERS.any? { |name| normalized.include?(name) }
        return if has_date && has_amount

        raise FatalError, "Statement CSV must contain an Amount column and a supported date column"
      end

      def parse_row(row, source_row_number:)
        raw_payload = {
          "headers" => row.headers.map { |header| header&.to_s },
          "values" => row.fields
        }

        return failed_row(source_row_number, raw_payload, "unsupported_row_shape", "Row has more values than named headers") if row.headers.any?(&:nil?)

        posted_raw = value_for(row, POSTED_DATE_HEADERS)
        transaction_raw = value_for(row, TRANSACTION_DATE_HEADERS)
        date_error = validate_dates(posted_raw, transaction_raw)
        return failed_row(source_row_number, raw_payload, date_error[:code], date_error[:message]) if date_error

        amount_raw = value_for(row, AMOUNT_HEADERS)
        return failed_row(source_row_number, raw_payload, "missing_amount", "Amount is missing") if amount_raw.blank?

        amount_cents = parse_amount(amount_raw)
        return failed_row(source_row_number, raw_payload, "invalid_amount", "Amount is not a valid signed decimal value") if amount_cents.nil?

        raw_description = value_for(row, DESCRIPTION_HEADERS).to_s
        normalized_description = raw_description.gsub(/\s+/, " ").strip

        {
          source_row_number: source_row_number,
          source_transaction_id: value_for(row, TRANSACTION_ID_HEADERS).to_s.strip.presence,
          posted_on: parse_date(posted_raw),
          transaction_on: parse_date(transaction_raw),
          raw_description: raw_description,
          normalized_description: normalized_description,
          merchant_key: nil,
          amount_cents: amount_cents,
          raw_payload: raw_payload,
          status: "parsed",
          error_code: nil,
          error_message: nil
        }
      end

      def failed_row(source_row_number, raw_payload, code, message)
        {
          source_row_number: source_row_number,
          source_transaction_id: value_from_payload(raw_payload, TRANSACTION_ID_HEADERS).to_s.strip.presence,
          posted_on: nil,
          transaction_on: nil,
          raw_description: value_from_payload(raw_payload, DESCRIPTION_HEADERS).to_s,
          normalized_description: nil,
          merchant_key: nil,
          amount_cents: nil,
          raw_payload: raw_payload,
          status: "failed",
          error_code: code,
          error_message: message
        }
      end

      def validate_dates(posted_raw, transaction_raw)
        if posted_raw.blank? && transaction_raw.blank?
          return { code: "missing_date", message: "Posting or transaction date is missing" }
        end
        if posted_raw.present? && parse_date(posted_raw).nil?
          return { code: "invalid_date", message: "Posting date is invalid" }
        end
        if transaction_raw.present? && parse_date(transaction_raw).nil?
          return { code: "invalid_date", message: "Transaction date is invalid" }
        end

        nil
      end

      def parse_date(raw)
        return if raw.blank?

        value = raw.to_s.strip
        DATE_FORMATS.each do |format|
          return Date.strptime(value, format)
        rescue Date::Error
          next
        end
        nil
      end

      def parse_amount(raw)
        Statements::DecimalCents.call(raw)
      rescue Statements::DecimalCents::InvalidAmount
        nil
      end

      def value_for(row, candidates)
        index = matching_header_index(row.headers, candidates)
        index ? row.fields[index] : nil
      end

      def value_from_payload(payload, candidates)
        index = matching_header_index(payload.fetch("headers"), candidates)
        index ? payload.fetch("values")[index] : nil
      end

      def matching_header_index(headers, candidates)
        normalized_candidates = candidates.map { |candidate| normalize_header(candidate) }
        headers.index do |header|
          header && normalized_candidates.include?(normalize_header(header))
        end
      end

      def normalize_header(header)
        header.to_s.downcase.strip.gsub(/\s+/, " ")
      end
    end
  end
end
