require "test_helper"

class AccountTest < ActiveSupport::TestCase
  def test_valid_factory
    assert build(:account).valid?
  end
end
