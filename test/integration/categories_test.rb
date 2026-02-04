# test/integration/categories_test.rb
require "test_helper"

class CategoriesTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user)
  end

  def test_edit_category_group_and_archive
    sign_in(@user)

    category = FactoryBot.create(
      :category,
      name: "Power",
      group: "Utilities",
      archived: false
    )

    patch category_path(category), params: {
      category: {
        group: "Bills",
        archived: "1"
      }
    }

    assert_redirected_to categories_path
    category.reload

    assert_equal "Bills", category.group
    assert_equal true, category.archived
  end
end
