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
        options[:channel_alert] = true unless options[:channel_alert] == false
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

      it "should try to switch to the backup channel (if available)" do
        channel.should_receive(:switch_to_backup)
        subject.message_rejected(transceiver, ao_message.id, pdu)
      end

      context "and there is a backup channel available" do
        before do
          channel.stub(:switch_to_backup).and_return(true)
        end

        it "should include alert that the channel is switching to backup" do
          assert_alert("Switching to backup")
          subject.message_rejected(transceiver, ao_message.id, pdu)
        end
      end

      context "and there is no backup channel available" do
        before do
          channel.stub(:switch_to_backup).and_return(false)
        end

        it "should log that no backup channel is available but not send an email" do
          assert_alert("WARNING: No backup channel available", :channel_alert => false)
          subject.message_rejected(transceiver, ao_message.id, pdu)
        end
      end
    end
  end
end
