require "bigdecimal"

module Statements
  class DecimalCents
    class InvalidAmount < StandardError; end

    FORMAT = /\A[+-]?\d+(?:\.\d{1,2})?\z/

    def self.call(value)
      raw = value.to_s.strip
      raise InvalidAmount, "amount is missing" if raw.empty?

      normalized = raw.delete(",$").strip
      unless normalized.match?(FORMAT)
        raise InvalidAmount, "amount must be a decimal value with no more than two fractional digits"
      end

      (BigDecimal(normalized) * 100).to_i
    rescue ArgumentError
      raise InvalidAmount, "amount is not a valid decimal value"
    end
  end
end
