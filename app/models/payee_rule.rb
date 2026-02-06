class PayeeRule < ApplicationRecord
  belongs_to :category

  MATCH_TYPES = %w[contains starts_with regex].freeze

  validates :pattern, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES }

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
end
