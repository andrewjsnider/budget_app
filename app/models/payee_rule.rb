class PayeeRule < ApplicationRecord
  belongs_to :category

  MATCH_TYPES = %w[contains starts_with regex].freeze

  validates :pattern, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES }
  validate :regex_pattern_is_valid

  def matches?(description)
    d = description.to_s
    p = pattern.to_s

    case match_type
    when "contains"
      d.downcase.include?(p.downcase)
    when "starts_with"
      d.downcase.start_with?(p.downcase)
    when "regex"
      Regexp.new(p, Regexp::IGNORECASE).match?(d)
    else
      false
    end
  rescue RegexpError
    false
  end

  private

  def regex_pattern_is_valid
    return unless match_type == "regex" && pattern.present?

    Regexp.new(pattern)
  rescue RegexpError => e
    errors.add(:pattern, "is not a valid regular expression: #{e.message}")
  end
end
