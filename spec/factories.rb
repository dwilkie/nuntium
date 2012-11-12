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

    factory :get_ack_application_with_url do
      delivery_ack_method 'get'
      delivery_ack_url 'http://www.example.com'
    end
  end

  # not a valid factory
  factory :channel do
    account
    sequence(:name) {|n| "name#{n}" }
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

    factory :ao_message_from_bidirectional_smpp_channel do
      association :channel, :factory => :bidirectional_smpp_channel
    end
  end
end
