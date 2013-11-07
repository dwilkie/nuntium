require 'spec_helper'

describe SmppTransceiverDelegate do
  let(:transceiver) { double(Smpp::Transceiver) }
  let(:channel) { create_channel }

  subject { SmppTransceiverDelegate.new(transceiver, channel) }

  def create_channel(*args)
    args.unshift(:bidirectional)
    create(:smpp_channel, *args)
  end

  def channel_configuration(config = {})
    attributes_for(:smpp_channel)[:configuration].merge(config)
  end

  describe "#send_message(id, from, to, text, options = {})" do
    let(:message_id) { 1 }
    let(:from) { "855381234567" }
    let(:to) { "855387654321" }
    let(:csms_transmission) { nil }

    let(:configuration) {
      channel_configuration(
        :mt_encodings => [channel_mt_encoding],
        :endianness_mt => channel_endianness_mt,
        :csms_transmission => csms_transmission,
        :mt_max_length => "140"

      )
    }

    def do_send_message
      subject.send_message(message_id, from, to, text)
    end

    context "channel#mt_encodings => ['ucs-2']" do
      let(:channel_mt_encoding) { 'ucs-2' }
      let(:asserted_data_coding) { 8 }

      context "channel#endianness_mt => 'big'"  do
        let(:channel_endianness_mt) { 'big' }
        let(:asserted_encoding_key) { channel_mt_encoding + "be" }

        let(:encoded_text) { Iconv.new(asserted_encoding_key, 'utf-8').iconv(text) }

        context "when sending a long message" do
          let(:text) { "t" * 141 }

          def create_channel(*args)
            options = args.extract_options!
            args << {:configuration => configuration}.merge(options)
            super(*args)
          end

          describe "channel#csms_transmission => 'auto'" do
            let(:csms_transmission) { 'auto' }

            before do
              transceiver.stub(:send_concat_mt)
            end

            it "should try to send a csms using Smpp::Transceiver#send_concat_mt" do
              transceiver.should_receive(
                :send_concat_mt
              ).with(message_id, from, to, encoded_text, {:data_coding => asserted_data_coding})
              do_send_message
            end
          end

          describe "to any other channel" do
            before do
              transceiver.stub(:send_mt)
            end

            it "should try to send 3 MT messages using Smpp::Transceiver#send_mt" do
              transceiver.should_receive(
                :send_mt
              ).exactly(3).times
              do_send_message
            end
          end
        end
      end
    end
  end
end
