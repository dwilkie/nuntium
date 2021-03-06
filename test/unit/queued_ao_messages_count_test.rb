require 'test_helper'

class QueuedAoMessagesCountTest < ActiveSupport::TestCase
  def setup
    @chan = QstServerChannel.make
  end

  test "default count is zero" do
    assert_equal 0, @chan.account.queued_ao_messages_count_by_channel_id[@chan.id]
  end

  test "when an ao gets queued count gets incremented" do
    AoMessage.make :account => @chan.account, :channel => @chan, :state => 'queued'
    assert_equal 1, @chan.account.queued_ao_messages_count_by_channel_id[@chan.id]

    AoMessage.make :account => @chan.account, :channel => @chan, :state => 'queued'
    assert_equal 2, @chan.account.queued_ao_messages_count_by_channel_id[@chan.id]
  end

  test "when an ao gets out of queued count gets decremented" do
    msg = AoMessage.make :account => @chan.account, :channel => @chan, :state => 'queued'
    assert_equal 1, @chan.account.queued_ao_messages_count_by_channel_id[@chan.id]

    msg.state = 'delivered'
    msg.save!

    assert_equal 0, @chan.account.queued_ao_messages_count_by_channel_id[@chan.id]
  end

  test "when an ao does not change its state count is the same" do
    msg = AoMessage.make :account => @chan.account, :channel => @chan, :state => 'queued'
    assert_equal 1, @chan.account.queued_ao_messages_count_by_channel_id[@chan.id]

    msg.tries = 2
    msg.save!

    assert_equal 1, @chan.account.queued_ao_messages_count_by_channel_id[@chan.id]
  end

  test "when an ao gets created but it's not queued don't increment" do
    AoMessage.make :account => @chan.account, :channel => @chan, :state => 'pending'
    AoMessage.make :account => @chan.account, :channel => @chan, :state => 'pending'
    AoMessage.make :account => @chan.account, :channel => @chan, :state => 'pending'

    assert_equal 0, @chan.account.queued_ao_messages_count_by_channel_id[@chan.id]
  end
end
