require "test_helper"

class AuthRequiredTest < ActionDispatch::IntegrationTest
  def test_root_requires_authentication
    get root_path
    assert_response :redirect
  end

  def test_root_works_when_signed_in
    user = User.create!(
      email_address: "al@localhost",
      password: "password123",
      password_confirmation: "password123"
    )

    sign_in user

    get root_path
    assert_response :success
    assert_includes response.body, "Budget"
  end
end
