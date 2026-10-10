module StatementEntries
  class DescriptionNormalizer
    NOISE_TOKENS = %w[pos debit credit purchase card transaction pending].freeze

    def self.call(description)
      ActiveSupport::Inflector.transliterate(utf8(description))
        .downcase
        .gsub(/[^a-z0-9]+/, " ")
        .split
        .reject { |token| NOISE_TOKENS.include?(token) }
    end

    def self.match?(left, right)
      left_tokens = call(left)
      right_tokens = call(right)
      return false if left_tokens.empty? || right_tokens.empty?
      return true if left_tokens == right_tokens

      shorter, longer = [ left_tokens, right_tokens ].sort_by(&:length)
      longer.first(shorter.length) == shorter
    end

    def self.exact?(left, right)
      utf8(left).downcase.strip.gsub(/\s+/, " ") == utf8(right).downcase.strip.gsub(/\s+/, " ")
    end

    def self.utf8(value)
      value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
    end
    private_class_method :utf8
  end
end
