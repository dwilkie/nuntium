FactoryGirl.define do
  factory :account do
    name { "account" }
    password { "password" }
    password_confirmation { password }
  end

  factory :application do
    name { "application" }
    account
    password { "password" }
    password_confirmation { password }
  end
end
