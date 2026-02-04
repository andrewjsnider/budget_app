require "test_helper"

class IncomeSourcesTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user, password: "password123", password_confirmation: "password123")
    sign_in(@user)

    @account = FactoryBot.create(:account, name: "Checking", kind: "asset", archived: false)
    @income_cat = FactoryBot.create(:category, name: "Job Income", kind: "income", group: "income", archived: false)
  end

  def test_index_renders
    get income_sources_path
    assert_response :success
    assert_includes response.body, "Income sources"
  end

  def test_create_income_source
    assert_difference -> { IncomeSource.count }, 1 do
      post income_sources_path, params: {
        income_source: {
          name: "Job A",
          kind: "w2",
          active: true,
          account_id: @account.id,
          category_id: @income_cat.id
        }
      }
    end

    assert_redirected_to income_sources_path
    follow_redirect!
    assert_includes response.body, "Job A"
  end

  def test_update_income_source
    src = IncomeSource.create!(name: "Job B", kind: "w2", active: true, account: @account, category: @income_cat)

    patch income_source_path(src), params: { income_source: { name: "Job B Updated", active: false } }
    assert_redirected_to income_sources_path

    src.reload
    assert_equal "Job B Updated", src.name
    assert_equal false, src.active
  end
end
