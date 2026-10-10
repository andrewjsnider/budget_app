require "test_helper"

class ReconciliationTest < ActiveSupport::TestCase
  def test_end_date_cannot_precede_start_date
    reconciliation = build(
      :reconciliation,
      starts_on: Date.new(2026, 8, 31),
      ends_on: Date.new(2026, 8, 1)
    )

    assert_not reconciliation.valid?
    assert_includes reconciliation.errors[:ends_on], "must be on or after the start date"
  end

  def test_finalized_periods_cannot_overlap_for_the_same_account
    account = create(:account)
    create(
      :reconciliation,
      account: account,
      starts_on: Date.new(2026, 8, 1),
      ends_on: Date.new(2026, 8, 31)
    )
    overlapping = build(
      :reconciliation,
      account: account,
      starts_on: Date.new(2026, 8, 31),
      ends_on: Date.new(2026, 9, 30)
    )

    assert_not overlapping.valid?
    assert_includes overlapping.errors[:base], "Finalized reconciliation period overlaps an existing finalized reconciliation"
  end
end
