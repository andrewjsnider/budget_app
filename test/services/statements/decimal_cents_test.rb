require "test_helper"

class StatementsDecimalCentsTest < ActiveSupport::TestCase
  def test_converts_decimal_dollars_without_floating_point
    assert_equal 123_456, Statements::DecimalCents.call("$1,234.56")
    assert_equal(-123_456, Statements::DecimalCents.call("-1,234.56"))
    assert_equal 0, Statements::DecimalCents.call("0.00")
  end

  def test_rejects_more_than_two_fractional_digits
    assert_raises(Statements::DecimalCents::InvalidAmount) do
      Statements::DecimalCents.call("1.234")
    end
  end
end
