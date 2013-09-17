require 'spec_helper'

describe "smpp_service.rb" do
  def create_channel(options = {})
    create(:smpp_channel, :bidirectional, {:application => application}.merge(options))
  end

  let(:application) { create(:application) }
  let(:channel) { create_channel }
  let(:transceiver) { double(Smpp::Transceiver) }
  let(:receiver) { double(Smpp::Receiver) }
  let(:transmitter) { double(Smpp::Transmitter) }

  describe SmppGateway do
    let(:ao_message) { create(:ao_message, :channel => channel) }
    let(:pdu) { mock(Smpp::Pdu::SubmitSmResponse) }

    let(:config) do
      {
        :host => channel.host,
        :port => channel.port,
        :system_id => channel.user,
        :password => channel.password,
        :system_type => channel.system_type,
        :interface_version => 52,
        :source_ton  => channel.source_ton.to_i,
        :source_npi => channel.source_npi.to_i,
        :destination_ton => channel.destination_ton.to_i,
        :destination_npi => channel.destination_npi.to_i,
        :source_address_range => '',
        :destination_address_range => '',
        :enquire_link_delay_secs => 10
      }
    end

    subject { SmppGateway.new(channel) }

    describe "connecting and stopping" do
      def create_transmitter_receiver_channel
        channel = create_channel
        channel.bind_type = "transmitter/receiver"
        channel.save!
        channel
      end

      before do
        EM.stub(:connect)
      end

      describe "#connect" do
        def assert_transceiver_set(asserted_transceiver)
          subject.instance_variable_get(:@transceiver).should == asserted_transceiver
        end

        context "given channel#bind_type is nil" do
          it "should connect using a transceiver" do
            EM.should_receive(:connect).with(
              channel.host, channel.port, MyTransceiver, config, subject
            ).and_return(transceiver)
            subject.connect
            assert_transceiver_set(transceiver)
          end
        end

        context "given channel#bind_type is 'transmitter/receiver'" do
          let(:channel) { create_transmitter_receiver_channel }

          it "should connect using a receiver and transmitter" do
            EM.should_receive(:connect).with(
              channel.host, channel.port, MyReceiver, config, subject
            ).and_return(receiver)
            EM.should_receive(:connect).with(
              channel.host, channel.port, MyTransmitter, config, subject
            ).and_return(transmitter)
            subject.connect
            assert_transceiver_set(transmitter)
            subject.instance_variable_get(:@receiver).should == receiver
            subject.instance_variable_get(:@transmitter).should == transmitter
          end
        end
      end

      describe "#stop" do
        context "given channel#bind_type is nil" do
          before do
            EM.stub(:connect).and_return(transceiver)
            subject.connect
          end

          it "should close the connection on the transceiver" do
            transceiver.should_receive(:close_connection)
            subject.stop
          end
        end

        context "given channel#bind_type is 'transmitter/receiver'" do
          let(:channel) { create_transmitter_receiver_channel }

          before do
            EM.stub(:connect).and_return(receiver, transmitter)
            subject.connect
          end

          it "should close the connection on the receiver and transmitter" do
            receiver.should_receive(:close_connection)
            transmitter.should_receive(:close_connection)
            subject.stop
          end
        end
      end
    end

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
end
