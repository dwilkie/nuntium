FactoryGirl.define do
  # channel traits

  trait :default_channel_attributes do
    account
    sequence(:name) {|n| "channel#{n}" }
    protocol "protocol"
    kind "smpp"
  end

  trait :bidirectional do
    direction { Channel::Bidirectional }
  end

  trait :with_application do
    application
  end

  factory :account do
    sequence(:name) {|n| "account#{n}" }
    password { "password" }
    password_confirmation { password }

    trait :with_alert_emails do
      alert_emails "foo@example.com"
    end
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

    trait :get_ack do
      delivery_ack_method 'get'
    end

    trait :post_ack do
      delivery_ack_method 'post'
    end

    trait :recently_prioritized_backup_channel do
      prioritized_backup_channel_at { Time.now }
    end

    trait :not_recently_prioritized_backup_channel do
      prioritized_backup_channel_at { 5.minutes.ago }
    end

    trait :with_ao_rules do
      ignore do
        suggested_channels {}
      end

      ao_rules do
        rules = [{
         "actions" => [{
            "value" => "",
            "property" => "cancel"
          }],
          "stop" => "yes",
          "matchings" => [{
            "value" => "",
            "property" => "body",
            "operator" => "equals"
          }]
        }]

        suggested_channels.each do |name, matching|
          rules << {
            "actions" => [{
              "value" => name.to_s, "property" => "suggested_channel"
            }],
            "stop" => "yes",
            "matchings" => [{
              "value" => matching.to_s,
              "property" => "to",
              "operator" => "regex"
            }]
          }
        end

        rules
      end
    end
  end

  # not a valid factory
  factory :channel do
    default_channel_attributes
  end

  factory :smpp_channel do
    default_channel_attributes
    configuration {{
      :host => "http://www.example.com",
      :port => 1234,
      :source_ton => 0,
      :source_npi => 0,
      :destination_ton => 0,
      :destination_npi => 0,
      :user => "user",
      :password => "password",
      :system_type => 'smpp',
      :mt_encodings => ['ascii'],
      :default_mo_encoding => 'ascii',
      :mt_csms_method => 'udh'
    }}
  end

  factory :ao_message do
    account

    trait :with_token do
      sequence(:token) { |n| "6d227b10-b889-f87f-1b29-79b26636d41#{n}" }
    end

    trait :with_custom_attributes do
      custom_attributes { { 'foo' => 'bar' } }
    end
  end
end
