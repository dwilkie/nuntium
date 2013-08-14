require 'spec_helper'

describe SmppChannel do
  let(:account) { create(:account) }
  let(:application) { create(:application) }
  let(:subject) { create(:smpp_channel, :bidirectional, :application => application, :account => account) }
  let(:amqp_channel) { double(AMQP::Channel) }
  let(:amqp_queue) { double(AMQP::Queue) }
  let(:amqp_exchange) { double(AMQP::Exchange) }

  describe "#touch_managed_process" do
    before do
      AMQP::Channel.stub(:new).and_return(amqp_channel)
      amqp_channel.stub(:queue).and_return(amqp_queue)
      amqp_channel.stub(:topic).and_return(amqp_exchange)
      amqp_queue.stub(:bind).and_return(amqp_queue)
      amqp_exchange.stub(:publish).and_return(amqp_exchange)
      subject
    end

    it "should restart the managed process" do
      amqp_exchange.should_receive(:publish).with(/RestartProcessJob/, anything)
      subject.touch_managed_process
    end
  end
end
