require "test_helper"

class TransactionSearchTest < ActiveSupport::TestCase
  setup do
    @month = Date.new(2026, 9, 1)
    @checking = create(:account, name: "Puget Checking")
    @savings = create(:account, name: "Rainy Day Savings", kind: "savings")
    @coffee = create(:category, name: "Coffee", group: "Food")
    @income = create(:category, name: "Salary", kind: "income", group: "Income")
  end

  test "searches descriptions case-insensitively" do
    match = transaction(description: "PUGET Sound Coffee", amount_cents: -650)
    transaction(description: "Corner market", amount_cents: -700)

    assert_equal [ match ], search(q: "sound").to_a
  end

  test "searches associated account and category names" do
    account_match = transaction(description: "Transfer", account: @savings, amount_cents: -1000)
    category_match = transaction(description: "Morning stop", category: @income, amount_cents: 1000)

    assert_equal [ account_match ], search(q: "rainy").to_a
    assert_equal [ category_match ], search(q: "salary").to_a
  end

  test "searches linked statement merchant and reference fields without duplicates" do
    match = transaction(description: "Imported transaction", amount_cents: -1000)
    create(
      :statement_entry,
      ledger_transaction: match,
      resolution_status: "matched",
      resolved_at: Time.current,
      raw_description: "Original Puget Merchant",
      normalized_description: "original puget merchant",
      merchant_key: "puget-merchant",
      source_transaction_id: "REF-2026-123"
    )

    assert_equal [ match ], search(q: "puget-merchant").to_a
    assert_equal [ match ], search(q: "ref-2026-123").to_a
  end

  test "filters by account" do
    match = transaction(account: @checking, amount_cents: -1000)
    transaction(account: @savings, amount_cents: -1000)

    assert_equal [ match ], search(account_id: @checking.id).to_a
  end

  test "filters by category" do
    match = transaction(category: @coffee, amount_cents: -1000)
    transaction(category: @income, amount_cents: 1000)

    assert_equal [ match ], search(category_id: @coffee.id).to_a
  end

  test "an explicit date range replaces the normal month range" do
    before = transaction(occurred_on: Date.new(2026, 8, 31), amount_cents: -1000)
    inside = transaction(occurred_on: Date.new(2026, 9, 15), amount_cents: -1100)
    after = transaction(occurred_on: Date.new(2026, 10, 1), amount_cents: -1200)

    results = search(start_date: "2026-08-31", end_date: "2026-09-15").to_a

    assert_includes results, before
    assert_includes results, inside
    refute_includes results, after
  end

  test "searches an exact positive signed amount" do
    match = transaction(amount_cents: 12_550)
    transaction(amount_cents: -12_550)

    assert_equal [ match ], search(q: "125.50").to_a
  end

  test "searches an exact negative signed amount" do
    transaction(amount_cents: 12_550)
    match = transaction(amount_cents: -12_550)

    assert_equal [ match ], search(q: "-125.50").to_a
  end

  test "combines search and filters" do
    match = transaction(description: "Coffee shop", account: @checking, category: @coffee, amount_cents: -900)
    transaction(description: "Coffee shop", account: @savings, category: @coffee, amount_cents: -900)
    transaction(description: "Coffee shop", account: @checking, category: @income, amount_cents: 900)

    results = search(q: "coffee", account_id: @checking.id, category_id: @coffee.id, flow: "outflow")

    assert_equal [ match ], results.to_a
  end

  test "returns no matches" do
    transaction(description: "Coffee shop", amount_cents: -900)

    assert_empty search(q: "missing").to_a
  end

  test "never broadens the supplied authorization scope" do
    permitted = transaction(description: "Shared description", account: @checking, amount_cents: -1000)
    transaction(description: "Shared description", account: @savings, amount_cents: -1000)
    authorized_scope = Transaction.where(account_id: @checking.id)

    assert_equal [ permitted ], search({ q: "shared" }, scope: authorized_scope).to_a
  end

  test "amount search cannot escape the supplied authorization scope" do
    transaction(account: @savings, amount_cents: -12_550)
    authorized_scope = Transaction.where(account_id: @checking.id)

    assert_empty search({ q: "-125.50" }, scope: authorized_scope).to_a
  end

  test "uses the existing date-descending default order" do
    older = transaction(occurred_on: @month + 2, amount_cents: -1000)
    newer = transaction(occurred_on: @month + 3, amount_cents: -1000)

    assert_equal [ newer, older ], search.to_a
  end

  test "sorts every supported column in both directions" do
    alpha_account = create(:account, name: "Alpha Account")
    zulu_account = create(:account, name: "Zulu Account")
    alpha_category = create(:category, name: "Alpha Category")
    zulu_category = create(:category, name: "Zulu Category")
    first = transaction(
      description: "Alpha",
      account: alpha_account,
      category: alpha_category,
      occurred_on: @month + 1,
      amount_cents: -2000
    )
    second = transaction(
      description: "Zulu",
      account: zulu_account,
      category: zulu_category,
      occurred_on: @month + 2,
      amount_cents: 1000
    )

    %w[date description account category amount].each do |sort_key|
      ascending = search(sort: sort_key, direction: "asc").to_a
      descending = search(sort: sort_key, direction: "desc").to_a

      assert_equal [ first, second ], ascending, "expected #{sort_key} ascending"
      assert_equal [ second, first ], descending, "expected #{sort_key} descending"
    end
  end

  test "search and filters compose with sorting" do
    lower = transaction(description: "Coffee roaster one", account: @checking, amount_cents: -2000)
    higher = transaction(description: "Coffee roaster two", account: @checking, amount_cents: -1000)
    transaction(description: "Tea", account: @checking, amount_cents: -3000)
    transaction(description: "Coffee elsewhere", account: @savings, amount_cents: -3000)

    results = search(q: "roaster", account_id: @checking.id, sort: "amount", direction: "asc")

    assert_equal [ lower, higher ], results.to_a
  end

  test "unsupported sort and direction values fall back safely" do
    older = transaction(occurred_on: @month + 2, description: "Zulu", amount_cents: -1000)
    newer = transaction(occurred_on: @month + 3, description: "Alpha", amount_cents: -2000)

    assert_equal [ newer, older ], search(sort: "created_at; DROP TABLE transactions", direction: "asc").to_a
    assert_equal [ newer, older ], search(sort: "date", direction: "sideways").to_a
  end

  test "associated sorting does not duplicate transactions" do
    one = transaction(account: @checking, amount_cents: -1000)
    two = transaction(account: @checking, amount_cents: -1100)

    results = search(sort: "account", direction: "asc").to_a

    assert_equal [ one.id, two.id ].sort, results.map(&:id).sort
    assert_equal results.map(&:id).uniq, results.map(&:id)
  end

  test "filters by flow reconciliation and cleared state" do
    reconciled = transaction(amount_cents: 1000, cleared: true, reconciled_at: Time.current)
    uncleared = transaction(amount_cents: -1000, cleared: nil)

    assert_equal [ reconciled ], search(flow: "inflow", reconciliation_status: "reconciled", cleared_status: "cleared").to_a
    assert_equal [ uncleared ], search(flow: "outflow", reconciliation_status: "unreconciled", cleared_status: "uncleared").to_a
  end

  private

  def transaction(**attributes)
    create(
      :transaction,
      account: @checking,
      category: @coffee,
      occurred_on: @month + 10,
      **attributes
    )
  end

  def search(params = {}, scope: Transaction.all, **keyword_params)
    params = params.merge(keyword_params)
    TransactionSearch.new(
      scope: scope,
      params: params,
      default_date_range: @month..@month.end_of_month
    ).call
  end
end
