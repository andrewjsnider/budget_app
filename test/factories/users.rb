FactoryBot.define do
  factory :user do
    email_address { "al@localhost" }
    password { "password123" }
    password_confirmation { "password123" }
  end
end