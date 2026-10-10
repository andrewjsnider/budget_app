require "digest"
require "json"

module Statements
  class SourceIdentity
    VERSION = "statement-entry-v1".freeze

    def self.base_key(row)
      source_transaction_id = row[:source_transaction_id].to_s.strip
      return "institution-id\0#{source_transaction_id}" if source_transaction_id.present?

      payload = row.fetch(:raw_payload)
      canonical_row = payload.fetch("headers").zip(payload.fetch("values")).map do |header, value|
        [ header.to_s.downcase.strip.gsub(/\s+/, " "), value ]
      end
      "canonical-row\0#{JSON.generate(canonical_row)}"
    end

    def self.call(account_id:, file_sha256:, base_key:, occurrence:)
      Digest::SHA256.hexdigest(
        [ VERSION, account_id, file_sha256, base_key, occurrence ].join("\0")
      )
    end
  end
end
