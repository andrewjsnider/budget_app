require "test_helper"

class Transactions::HistoricalImportTest < ActiveSupport::TestCase
  setup do
    @account = create(:account, import_key: "historical-#{SecureRandom.hex(4)}")
    @source = Rails.root.join("private", "historical-import-#{SecureRandom.hex(6)}.csv")
    @source.dirname.mkpath
  end

  teardown do
    FileUtils.remove_file(@source) if @source&.exist?
  end

  test "applies an exclusive cutoff and preserves signed amounts" do
    write_csv([
      [ "DEBIT", "10/08/2026", "Before", "-1.00", "DEBIT_CARD", "" ],
      [ "DEBIT", "10/09/2026", "On cutoff", "-2.00", "DEBIT_CARD", "" ],
      [ "DEBIT", "10/10/2026", "Expense", "-3.25", "DEBIT_CARD", "" ],
      [ "CREDIT", "10/11/2026", "Income", "125.50", "ACH_CREDIT", "" ]
    ])

    result = import(after: Date.new(2026, 10, 9), dry_run: false)

    assert_equal 4, result[:total_source_rows]
    assert_equal 2, result[:rows_at_or_before_cutoff]
    assert_equal 2, result[:eligible_rows]
    assert_equal 2, result[:created_count]
    assert_equal [ -325, 12_550 ], @account.transactions.order(:occurred_on).pluck(:amount_cents)
  end

  test "detects an existing transaction and a nearby normalized-description candidate" do
    create(:transaction, account: @account, occurred_on: Date.new(2026, 10, 10), description: "Existing purchase", amount_cents: -500)
    create(:transaction, account: @account, occurred_on: Date.new(2026, 10, 12), description: "Coffee Shop Main", amount_cents: -700)
    write_csv([
      [ "DEBIT", "10/10/2026", "Existing purchase", "-5.00", "DEBIT_CARD", "" ],
      [ "DEBIT", "10/13/2026", "COFFEE SHOP", "-7.00", "DEBIT_CARD", "" ],
      [ "DEBIT", "10/20/2026", "New", "-8.00", "DEBIT_CARD", "" ]
    ])

    result = import(after: Date.new(2026, 10, 9), dry_run: true)

    assert_equal 2, result[:definite_match_count]
    assert_equal 0, result[:ambiguous_count]
    assert_equal 1, result[:clear_new_count]
    assert_empty result[:ambiguous_rows]
  end

  test "reports ambiguous possible duplicates without choosing one" do
    first = create(:transaction, account: @account, occurred_on: Date.new(2026, 10, 10), description: "Market A", amount_cents: -1000)
    second = create(:transaction, account: @account, occurred_on: Date.new(2026, 10, 12), description: "Market B", amount_cents: -1000)
    write_csv([ [ "DEBIT", "10/11/2026", "Market", "-10.00", "DEBIT_CARD", "" ] ])

    result = import(after: Date.new(2026, 10, 9), dry_run: true)

    assert_equal 1, result[:ambiguous_count]
    assert_equal [ first.id, second.id ], result[:ambiguous_rows].first[:candidate_transactions].map { |candidate| candidate[:id] }
    assert_equal 2, result[:ambiguous_rows].first[:candidate_transactions].length
  end

  test "creates clear new rows and reruns idempotently" do
    write_csv([ [ "DEBIT", "10/10/2026", "New expense", "-4.50", "DEBIT_CARD", "" ] ])

    first = import(after: Date.new(2026, 10, 9), dry_run: false)
    second = import(after: Date.new(2026, 10, 9), dry_run: false)

    assert_equal 1, first[:created_count]
    assert_equal 1, second[:already_present_count]
    assert_equal 1, @account.transactions.count
    assert @account.transactions.first.import_hash.present?
  end

  test "applies safe rows while preserving and repeatedly reporting unresolved rows" do
    definite = create(
      :transaction,
      account: @account,
      occurred_on: Date.new(2026, 2, 2),
      description: "Existing definite",
      amount_cents: -1100
    )
    ambiguous_one = create(
      :transaction,
      account: @account,
      occurred_on: Date.new(2026, 2, 6),
      description: "POS DEBIT HCI CLEANING PRODUCTS HOLLIS NH",
      amount_cents: -2591
    )
    ambiguous_two = create(
      :transaction,
      account: @account,
      occurred_on: Date.new(2026, 2, 9),
      description: "HCI CLEANING PRODUCTS",
      amount_cents: -2591
    )
    untouched = [ definite, ambiguous_one, ambiguous_two ].to_h do |transaction|
      [ transaction.id, transaction.attributes ]
    end
    write_csv([
      [ "DEBIT", "02/02/2026", "Existing definite", "-11.00", "DEBIT_CARD", "" ],
      [ "DEBIT", "02/09/2026", "HCI CLEANING PRODUCTS", "-25.91", "DEBIT_CARD", "" ],
      [ "DEBIT", "02/10/2026", "Safe expense", "-12.34", "DEBIT_CARD", "" ],
      [ "CREDIT", "02/11/2026", "Safe income", "45.67", "ACH_CREDIT", "" ],
      [ "DEBIT", "02/12/2026", "Malformed", "not-an-amount", "DEBIT_CARD", "" ]
    ])

    first = import(after: Date.new(2026, 2, 1), dry_run: false)

    assert_equal :ok, first[:status]
    assert_equal 4, first[:eligible_rows]
    assert_equal 2, first[:created_count]
    assert_equal 1, first[:matched_existing_count]
    assert_equal 1, first[:ambiguous_skipped_count]
    assert_equal 1, first[:failed_count]
    assert_equal 4, first[:eligible]
    assert_equal 2, first[:created]
    assert_equal 1, first[:matched_existing]
    assert_equal 1, first[:ambiguous_skipped]
    assert_equal 1, first[:failed]
    assert first[:manual_review_required]
    assert_equal [ ambiguous_one.id, ambiguous_two.id ], first[:ambiguous_rows].sole[:candidate_transactions].pluck(:id)
    assert_equal [ -1234, 4567 ], @account.transactions.where(description: [ "Safe expense", "Safe income" ]).order(:occurred_on).pluck(:amount_cents)
    untouched.each { |id, attributes| assert_equal attributes, Transaction.find(id).attributes }

    second = import(after: Date.new(2026, 2, 1), dry_run: false)

    assert_equal 0, second[:created_count]
    assert_equal 3, second[:matched_existing_count]
    assert_equal 2, second[:already_present_count]
    assert_equal 1, second[:ambiguous_skipped_count]
    assert_equal 1, second[:ambiguous_rows].length
    assert_equal 1, second[:failed_count]
    assert_equal 5, @account.transactions.count
    untouched.each { |id, attributes| assert_equal attributes, Transaction.find(id).attributes }
  end

  test "reports malformed rows and makes no writes in a dry run" do
    write_csv([
      [ "DEBIT", "not-a-date", "Bad date", "-1.00", "DEBIT_CARD", "" ],
      [ "DEBIT", "10/10/2026", "Zero", "0.00", "DEBIT_CARD", "" ],
      [ "DEBIT", "10/11/2026", "Bad amount", "wat", "DEBIT_CARD", "" ]
    ])

    assert_no_difference("Transaction.count") do
      result = import(after: Date.new(2026, 10, 9), dry_run: true)
      assert_equal 3, result[:malformed_count]
    end
  end

  test "never modifies a reconciled matching transaction" do
    reconciliation = create(:reconciliation, account: @account)
    transaction = create(
      :transaction,
      account: @account,
      occurred_on: Date.new(2026, 10, 10),
      description: "Reconciled expense",
      amount_cents: -900,
      reconciled_at: Time.current,
      reconciliation: reconciliation
    )
    original = transaction.attributes.slice("amount_cents", "occurred_on", "description", "reconciled_at", "reconciliation_id", "import_hash")
    write_csv([ [ "DEBIT", "10/10/2026", "Reconciled expense", "-9.00", "DEBIT_CARD", "" ] ])

    result = import(after: Date.new(2026, 10, 9), dry_run: false)

    assert_equal 1, result[:definite_match_count]
    assert_equal original, transaction.reload.attributes.slice(*original.keys)
    assert_equal 1, @account.transactions.count
  end

  private

  def import(after:, dry_run:)
    Transactions::HistoricalImport.call(
      file_path: @source,
      account: @account,
      after: after,
      dry_run: dry_run
    )
  end

  def write_csv(rows)
    CSV.open(@source, "wb") do |csv|
      csv << [ "Details", "Posting Date", "Description", "Amount", "Type", "Balance", "Check or Slip #" ]
      rows.each { |row| csv << row + [ "", "" ] }
    end
  end
end
