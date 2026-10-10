module StatementEntries
  class DescriptionNormalizer
    NOISE_TOKENS = %w[pos debit credit purchase card transaction pending].freeze

    def self.call(description)
      ActiveSupport::Inflector.transliterate(description.to_s)
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
      left.to_s.downcase.strip.gsub(/\s+/, " ") == right.to_s.downcase.strip.gsub(/\s+/, " ")
    end
  end
end
