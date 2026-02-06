require "test_helper"

class PayeeRuleTest < ActiveSupport::TestCase
  def setup
    @category = FactoryBot.create(:category)
  end

  def test_matches_contains_case_insensitive
    rule = PayeeRule.new(pattern: "comcast", match_type: "contains", category: @category)
    assert rule.matches?("POS DEBIT COMCAST / XFINITY 800-266-2278")
    assert rule.matches?("comcast billpay")
    assert_not rule.matches?("SAFEWAY #2640")
  end

  def test_matches_starts_with
    rule = PayeeRule.new(pattern: "POS DEBIT", match_type: "starts_with", category: @category)
    assert rule.matches?("POS DEBIT COMCAST / XFINITY")
    assert_not rule.matches?("ACH DEBIT POS DEBIT COMCAST")
  end

  def test_matches_regex
    rule = PayeeRule.new(pattern: "comcast|xfinity", match_type: "regex", category: @category)
    assert rule.matches?("POS DEBIT COMCAST / XFINITY")
    assert_not rule.matches?("SAFEWAY #2640")
  end

  def test_bad_regex_does_not_raise
    rule = PayeeRule.new(pattern: "(", match_type: "regex", category: @category)
    assert_not rule.matches?("POS DEBIT COMCAST / XFINITY")
  end
end
