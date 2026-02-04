require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  def test_valid_factory
    assert build(:category).valid?
  end
end
