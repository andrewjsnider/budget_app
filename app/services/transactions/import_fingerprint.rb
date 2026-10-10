require "digest"

module Transactions
  class ImportFingerprint
    def self.call(account_id:, occurred_on:, description:, amount_cents:)
      normalized_description = description.to_s.downcase.strip.gsub(/\s+/, " ")
      Digest::SHA256.hexdigest(
        [ account_id, occurred_on.to_s, amount_cents.to_s, normalized_description ].join("|")
      )
    end
  end
end
