require "test_helper"

class TransactionsTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user)
    sign_in(@user)

    @account = FactoryBot.create(:account, name: "Checking", archived: false)
    @category = FactoryBot.create(:category, name: "Groceries", kind: "expense", group: "food", archived: false)
  end

  def test_index_renders
    get transactions_path(month: "2026-02")
    assert_response :success
    assert_includes response.body, "Transactions"
    assert_select "table.ui-table"
    assert_select "nav a[aria-current='page']", text: "Transactions"
  end

  def test_create_transaction
    assert_difference -> { Transaction.count }, 1 do
      post transactions_path, params: {
        transaction: {
          occurred_on: "2026-02-03",
          description: "Test",
          amount_cents: -1234,
          account_id: @account.id,
          category_id: @category.id
        }
      }
    end

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Test"
  end

  def test_category_dropdown_is_alphabetical
    FactoryBot.create(:category, name: "Zulu", kind: "expense", archived: false)
    FactoryBot.create(:category, name: "Alpha", kind: "income", archived: false)

    get new_transaction_path

    options = response.parsed_body.css("select[name='transaction[category_id]'] option").map { |option| option.text.strip }
    assert_operator options.index("Alpha"), :<, options.index("Zulu")
  end

  def test_transactions_can_filter_by_category
    account = FactoryBot.create(:account)
    cat1 = FactoryBot.create(:category, name: "Power")
    cat2 = FactoryBot.create(:category, name: "Water")

    FactoryBot.create(:transaction, account: account, category: cat1, occurred_on: Date.new(2026, 2, 5), amount_cents: -1000, description: "Electric")
    FactoryBot.create(:transaction, account: account, category: cat2, occurred_on: Date.new(2026, 2, 6), amount_cents: -1000, description: "Water bill")

    get transactions_path(month: "2026-02", category_id: cat1.id)
    assert_response :success

    body = @response.body
    assert_includes body, "Electric"
    refute_includes body, "Water bill"
  end

  def test_index_has_get_filters_count_and_no_match_state
    FactoryBot.create(
      :transaction,
      account: @account,
      category: @category,
      occurred_on: Date.new(2026, 2, 5),
      description: "Coffee"
    )

    get transactions_path(month: "2026-02", q: "missing")

    assert_response :success
    assert_select "form[method='get']"
    assert_select "input[name='q'][placeholder='Search transactions...']"
    assert_select "select[name='account_id']"
    assert_select "select[name='category_id']"
    assert_select "input[name='start_date']"
    assert_select "input[name='end_date']"
    assert_select "select[name='flow']"
    assert_select "select[name='reconciliation_status']"
    assert_select "select[name='cleared_status']"
    assert_includes response.body, "0 matching transactions"
    assert_includes response.body, "No transactions match these filters."
    assert_select "a", text: "Clear filters", href: transactions_path
  end

  def test_sort_header_toggles_and_preserves_search_filters
    get transactions_path(
      month: "2026-02",
      q: "coffee",
      account_id: @account.id,
      category_id: @category.id,
      sort: "amount",
      direction: "desc"
    )

    assert_response :success
    assert_select "th[aria-sort='descending'] a", text: /Amount/ do |links|
      href = links.first["href"]
      assert_includes href, "direction=asc"
      assert_includes href, "q=coffee"
      assert_includes href, "account_id=#{@account.id}"
      assert_includes href, "category_id=#{@category.id}"
      assert_includes href, "month=2026-02"
    end
    assert_select "a", text: "Description" do |links|
      assert_includes links.first["href"], "sort=description"
      assert_includes links.first["href"], "direction=asc"
    end
  end

  def test_filter_form_preserves_selected_sort
    get transactions_path(month: "2026-02", sort: "date", direction: "asc")

    assert_select "form[method='get'] input[name='sort'][value='date']"
    assert_select "form[method='get'] input[name='direction'][value='asc']"
  end

  def test_clearing_filters_returns_the_normal_index
    visible = FactoryBot.create(
      :transaction,
      account: @account,
      category: @category,
      occurred_on: Date.current.beginning_of_month + 1,
      description: "Only Coffee"
    )
    hidden_by_search = FactoryBot.create(
      :transaction,
      account: @account,
      category: @category,
      occurred_on: Date.current.beginning_of_month + 2,
      description: "Only Tea"
    )

    get transactions_path(q: "coffee")
    assert_includes response.body, visible.description
    refute_includes response.body, hidden_by_search.description

    get transactions_path
    assert_response :success
    assert_includes response.body, visible.description
    assert_includes response.body, hidden_by_search.description
    refute_select "a", text: "Clear filters"
  end
end
