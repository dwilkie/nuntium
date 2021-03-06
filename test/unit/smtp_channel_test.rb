require 'test_helper'

class SmtpChannelTest < ActiveSupport::TestCase
  def setup
    @chan = SmtpChannel.make
  end

  [:host, :port].each do |field|
    test "should validate configuration presence of #{field}" do
      assert_validates_configuration_presence_of @chan, field
    end
  end

  test "should not save if port is not a number" do
    @chan.configuration[:port] = 'foo'
    assert_false @chan.save
  end

  test "should not save if port is negative" do
    @chan.configuration[:port] = -430
    assert_false @chan.save
  end

  include GenericChannelTest
end
