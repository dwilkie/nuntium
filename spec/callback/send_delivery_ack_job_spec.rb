require 'spec_helper'

describe SendDeliveryAckJob do
  let(:account) { create(:account) }
  let(:channel) { create(:bidirectional_smpp_channel, :account => account) }
  let(:ao_message) { create(:ao_message_from_bidirectional_smpp_channel, :account => account, :channel => channel) }

  include FakeWebHelpers

  describe "#perform" do
    def do_job(reference_application)
      job = SendDeliveryAckJob.new(
        account.id, reference_application.id, ao_message.id, ao_message.state
      )
      job.perform
    end

    context "for an application configured for GET acks" do
      let(:get_ack_application) { create(:get_ack_application_with_url, :account => account) }

      before do
        channel.application = get_ack_application
        channel.save!
        register_delivery_ack(:ao_message => ao_message)
      end

      it "should do make a GET request for the delivery ack" do
        do_job(get_ack_application)
        last_request.method.should == "GET"
      end
    end
  end
end
