FactoryGirl.define do
  factory :account do
    sequence(:name) {|n| "account#{n}" }
    password { "password" }
    password_confirmation { password }
  end

  factory :application do
    name { "application" }
    account
    password { "password" }
    password_confirmation { password }

    trait :with_auth do
      delivery_ack_user 'john'
      delivery_ack_password 'doe'
    end

    trait :with_url do
      delivery_ack_url 'http://www.example.com'
    end

    factory :get_ack_application_with_url do
      delivery_ack_method 'get'
      with_url

      factory :get_ack_application_with_url_and_auth do
        with_auth
      end
    end

    factory :post_ack_application_with_url do
      delivery_ack_method 'post'
      with_url

      factory :post_ack_application_with_url_and_auth do
        with_auth
      end
    end
  end

  # not a valid factory
  factory :channel do
    account
    sequence(:name) {|n| "channel#{n}" }
    protocol "protocol"
    kind "kind"

    trait :bidirectional do
      direction { Channel::Bidirectional }
    end

    trait :smpp do
      kind "smpp"
    end

    trait :with_application do
      application
    end

    factory :bidirectional_channel do
      bidirectional

      factory :bidirectional_smpp_channel do
        smpp
      end
    end

    factory :smpp_channel do
      smpp
    end
  end

  factory :ao_message do
    account

    trait :with_custom_attributes do
      custom_attributes { { 'foo' => 'bar' } }
    end

    factory :ao_message_from_bidirectional_smpp_channel do
      association :channel, :factory => :bidirectional_smpp_channel

      factory :ao_message_from_bidirectional_smpp_channel_with_custom_attributes do
        with_custom_attributes
      end
    end
  end
end
