require "csv"
require "digest"

module Transactions
  class CsvImport
    def self.call(account:, csv_text:, default_category:)
      new(account:, csv_text:, default_category:).call
    end

    def initialize(account:, csv_text:, default_category:)
      @account = account
      @csv_text = csv_text
      @default_category = default_category
    end

    def call
      text = @csv_text.to_s.sub(/\A\xEF\xBB\xBF/, "") # strip UTF-8 BOM if present
      col_sep = detect_col_sep(text)

      rows = CSV.parse(
        text,
        headers: true,
        col_sep: col_sep,
        liberal_parsing: true
      )

      return { ok: false, error: "CSV has no headers." } unless rows.headers&.any?

      imported = 0
      skipped  = 0
      failed   = 0
      errors   = []

      rows.each_with_index do |row, idx|
        attrs = build_attrs_from_row(row)
        next if attrs.nil?

        begin
          Transaction.create!(attrs)
          imported += 1
        rescue ActiveRecord::RecordNotUnique
          skipped += 1
        rescue ActiveRecord::RecordInvalid => e
          failed += 1
          errors << "Row #{idx + 2}: #{e.record.errors.full_messages.to_sentence}"
        rescue ActiveRecord::StatementInvalid => e
          failed += 1
          errors << "Row #{idx + 2}: #{e.message}"
        end
      end

      { ok: true, imported: imported, skipped: skipped, failed: failed, errors: errors.take(10) }
    rescue CSV::MalformedCSVError => e
      { ok: false, error: "Malformed file: #{e.message}" }
    rescue => e
      { ok: false, error: e.message }
    end

    private

    def detect_col_sep(text)
      sample = text.lines.first.to_s
      return "\t" if sample.include?("\t")
      ","
    end

    def build_attrs_from_row(row)
      date = parse_date(value_for(row, ["posting date", "date", "transaction date", "posted date"]))
      return nil unless date

      description = parse_description(value_for(row, ["description"]))
      description = description.to_s.gsub(/\s+/, " ").strip
      description = description[0, 255]

      raw_amount = dollars_to_cents(value_for(row, ["amount"]))
      return nil if raw_amount.nil?

      amount_cents = raw_amount.abs

      import_hash = fingerprint(
        date: date,
        description: description,
        amount_cents: amount_cents
      )

      {
        account: @account,
        occurred_on: date,
        description: description.presence || "Imported",
        amount_cents: amount_cents,
        category: category_for(raw_amount),
        cleared: true,
        import_hash: import_hash
      }
    end


    def value_for(row, candidates)
      headers = row.headers.compact.map(&:to_s)

      candidates.each do |candidate|
        cand = normalize(candidate)
        header = headers.find { |h| normalize(h) == cand }
        return row[header] if header
      end

      nil
    end

    def normalize(str)
      str.to_s.downcase.strip.gsub(/\s+/, " ")
    end

    def parse_date(raw)
      return nil if raw.blank?
      Date.strptime(raw.to_s.strip, "%m/%d/%Y")
    rescue
      Date.parse(raw.to_s)
    rescue
      nil
    end

    def parse_description(raw)
      raw.to_s.strip
    end

    def dollars_to_cents(raw)
      return nil if raw.blank?
      s = raw.to_s.strip.gsub(/[,$]/, "")
      bd = BigDecimal(s)
      (bd * 100).to_i
    rescue
      nil
    end

    def fingerprint(date:, description:, amount_cents:)
      normalized_desc = description.to_s.downcase.strip.gsub(/\s+/, " ")
      Digest::SHA256.hexdigest([@account.id, date.to_s, amount_cents.to_s, normalized_desc].join("|"))
    end

    def category_for(raw_amount)
      if raw_amount < 0
        @default_category # expense
      else
        income_category
      end
    end

    def income_category
      @income_category ||= Category.find_or_create_by!(name: "Imported Income") do |c|
        c.kind = "income"
        c.group = "Imported"
        c.archived = false
      end
    end
  end
end
