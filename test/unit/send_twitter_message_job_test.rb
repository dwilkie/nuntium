require 'test_helper'

class SendTwitterMessageJobTest < ActiveSupport::TestCase

  include Mocha::API

  def setup
    @channel = TwitterChannel.make
    @msg = AoMessage.make :account_id => @channel.account_id, :channel_id => @channel.id, :state => 'queued'
    @job = SendTwitterMessageJob.new @channel.account_id, @channel.id, @msg.id
  end

  test "send" do
    response = mock('response')
    response.stubs :id => 'twitter_id'

    client = mock('client')
    client.expects(:direct_message_create).with(@msg.to.without_protocol, @msg.subject_and_body).returns(response)

    TwitterChannel.expects(:new_client).with(@channel.configuration).returns(client)

    @job.perform

    @msg.reload
    assert_equal 'delivered', @msg.state
    assert_equal response.id, @msg.channel_relative_id
  end

  test "send unauthorized" do
    client = mock('client')
    client.expects(:direct_message_create).with(@msg.to.without_protocol, @msg.subject_and_body).raises(Twitter::Unauthorized.new(''))

    TwitterChannel.expects(:new_client).with(@channel.configuration).returns(client)

    begin
      @job.perform
    rescue
    else
      fail "Exepcted exception to be thrown"
    end

    @channel.reload
    assert_true @channel.enabled
  end

  [['general', Twitter::General], ['not_found', Twitter::NotFound]].each do |msg, ex|
    test "send #{msg} error" do
      client = mock('client')
      client.expects(:direct_message_create).with(@msg.to.without_protocol, @msg.subject_and_body).raises(ex.new(''))

      TwitterChannel.expects(:new_client).with(@channel.configuration).returns(client)

      @job.perform

      @msg.reload
      assert_equal 'failed', @msg.state

      @channel.reload
      assert_true @channel.enabled
    end
  end

end
