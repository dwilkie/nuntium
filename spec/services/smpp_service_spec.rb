require 'spec_helper'

describe SmppGateway do
  let(:application) { create(:application) }
  let(:channel) { create(:smpp_channel, :bidirectional, :application => application) }
  let(:ao_message) { create(:ao_message, :channel => channel) }
  let(:pdu) { mock(Smpp::Pdu::SubmitSmResponse) }
  let(:transceiver) { mock(Smpp::Transceiver) }

  subject { SmppGateway.new(channel) }

  describe "#message_rejected(transceiver, mt_message_id, pdu)" do
    context "the message fails due to a command status 8" do
      def assert_alert(msg, options = {})
        Rails.logger.should_receive(:warn).with(/#{msg}/)
        if options[:channel_alert]
          channel.should_receive(:alert).with(/#{msg}/)
        else
          channel.should_not_receive(:alert)
        end
      end

      before do
        pdu.stub(:command_status).and_return(8)
      end

      it "should not try to switch to the backup channel" do
        channel.should_not_receive(:switch_to_backup)
        assert_alert("Received command status 8")
        subject.message_rejected(transceiver, ao_message.id, pdu)
      end
    end
  end
end
