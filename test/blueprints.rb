require 'machinist/active_record'
require 'sham'

Sham.define do
  name { Faker::Name.name }
  email { Faker::Internet.email }
  username { Faker::Internet.user_name }
  url { Faker::Internet.domain_name }
  password { Faker::Name.name }
  number2(:unique => false) { (1..2).map { ('1'..'9').to_a.rand }.join }
  number8 { (1..8).map { ('1'..'9').to_a.rand }.join }
  number4 { (1..4).map { ('1'..'9').to_a.rand }.join }
  guid { (1..10).map { ('a'..'z').to_a.rand }.join }
end

Account.blueprint do
  name { Sham.username }
  password
  password_confirmation { password }
end

Application.blueprint do
  name { Sham.username }
  account
  interface { "rss" }
  password
  password_confirmation { password }
end

Application.blueprint :rss do
end

Application.blueprint :broadcast do
  configuration { {:strategy => 'broadcast'} }
end

[:http_get_callback, :http_post_callback, :qst_client].each do |kind|
  Application.blueprint kind do
    interface { kind.to_s }
    configuration { {:interface_url => Sham.url, :interface_user => Sham.username, :interface_password => Sham.password} }
  end
end

[AoMessage, AtMessage].each do |message|
  message.blueprint do
    from { "sms://#{Sham.number8}" }
    to { "sms://#{Sham.number8}" }
    subject { Faker::Lorem.sentence }
    body { Faker::Lorem.paragraph }
    timestamp { Time.at(946702800 + 86400 * rand(100)).getgm }
    guid
    state { 'queued' }
  end
  message.blueprint :email do
    from { "mailto://#{Sham.email}" }
    to { "mailto://#{Sham.email}" }
  end
end

Carrier.blueprint do
  country
  name
  guid
  prefixes { Sham.number2 }
end

QstClientChannel.blueprint do
  account
  name { Sham.guid }
  direction { Channel::Bidirectional }
  protocol { "sms" }
  enabled { true }
  configuration { {:url => Sham.url, :user => Sham.username, :password => Sham.password} }
end

QstServerChannel.blueprint do
  account
  name { Sham.guid }
  direction { Channel::Bidirectional }
  protocol { "sms" }
  enabled { true }
  address { Sham.number8 }
  configuration { {:password => 'secret', :password_confirmation => 'secret'} }
end

ClickatellChannel.blueprint do
  account
  name { Sham.guid }
  direction { Channel::Bidirectional }
  protocol { "sms" }
  enabled { true }
  configuration { {:user => Sham.username, :password => Sham.password, :api_id => Sham.guid, :from => Sham.number8, :incoming_password => Sham.password, :cost_per_credit => rand }}
end

DtacChannel.blueprint do
  account
  name { Sham.guid }
  direction { Channel::Bidirectional }
  protocol { "sms" }
  enabled { true }
  configuration { {:user => Sham.username, :password => Sham.password } }
end

IpopChannel.blueprint do
  account
  name { Sham.guid }
  direction { Channel::Bidirectional }
  protocol { "sms" }
  enabled { true }
  address { Sham.number8 }
  configuration { {:mt_post_url => Sham.url, :bid => '1', :cid => Sham.number8 } }
end

MultimodemIsmsChannel.blueprint do
  account
  name { Sham.guid }
  direction { Channel::Bidirectional }
  protocol { "sms" }
  enabled { true }
  configuration {{:host => Sham.url, :port => rand(1000) + 1, :user => Sham.username, :password => Sham.password, :time_zone => ActiveSupport::TimeZone.all.rand.name}}
end

Pop3Channel.blueprint do
  account
  name { Sham.guid }
  protocol { "mailto" }
  direction { Channel::Incoming }
  enabled { true }
  configuration { {:host => Sham.url, :port => rand(1000) + 1, :user => Sham.username, :password => Sham.password}}
end

SmtpChannel.blueprint do
  account
  name { Sham.guid }
  protocol { "mailto" }
  direction { Channel::Outgoing }
  enabled { true }
  configuration { {:host => Sham.url, :port => rand(1000) + 1, :user => Sham.username, :password => Sham.password}}
end

SmppChannel.blueprint do
  account
  name { Sham.guid }
  direction { Channel::Bidirectional }
  protocol { "sms" }
  enabled { true }
  configuration {{:host => Sham.url, :port => rand(1000) + 1, :source_ton => 0, :source_npi => 0, :destination_ton => 0, :destination_npi => 0, :user => Sham.username, :password => Sham.password, :system_type => 'smpp', :mt_encodings => ['ascii'], :default_mo_encoding => 'ascii', :mt_csms_method => 'udh' } }
end

TwilioChannel.blueprint do
  account
  name { Sham.guid }
  direction { Channel::Bidirectional }
  protocol { "sms" }
  enabled { true }
  configuration { {:account_sid => Sham.guid, :auth_token => Sham.guid, :from => Sham.number8, :incoming_password => Sham.guid } }
end

TwitterChannel.blueprint do
  account
  name { Sham.guid }
  direction { Channel::Bidirectional }
  protocol { "twitter" }
  enabled { true }
  configuration { {:token => Sham.guid, :secret => Sham.guid, :screen_name => Sham.username} }
end

XmppChannel.blueprint do
  account
  name { Sham.guid }
  direction { Channel::Bidirectional }
  protocol { "xmpp" }
  enabled { true }
  configuration { {:user => Sham.username, :domain => Sham.url, :password => Sham.password, :server => Sham.url, :port => 1 + rand(1000), :resource => Sham.username} }
end

Ticket.blueprint do
  code { Sham.number4 }
  secret_key { Sham.guid }
end

Ticket.blueprint :pending do
  status { 'pending' }
end

Country.blueprint do
  name
  iso2 { (1..2).map { ('a'..'z').to_a.rand }.join }
  iso3 { (1..3).map { ('a'..'z').to_a.rand }.join }
  phone_prefix { Sham.number2 }
end

ManagedProcess.blueprint do
  account
  name
  start_command { Sham.guid }
  stop_command { Sham.guid }
  pid_file { Sham.guid }
  log_file { Sham.guid }
end
