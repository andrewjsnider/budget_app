require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  def test_factory
    assert build(:transaction).valid?
  end
end
