require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = FactoryBot.create(:user)
  end

  def test_show_no_user
    get root_path
    assert_response :redirect
  end

  def test_show_no_user
    sign_in @user
    get root_path
    assert_response :success
  end
end
