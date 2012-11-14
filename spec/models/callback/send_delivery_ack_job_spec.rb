require 'spec_helper'

describe SendDeliveryAckJob do
  let(:account) { create(:account) }
  let(:channel) { create(:bidirectional_smpp_channel, :account => account) }

  let(:ao_message) do
    create(
      :ao_message_from_bidirectional_smpp_channel,
      :account => account, :channel => channel
    )
  end

  let(:custom_attributes_ao_message) do
    create(
      :ao_message_from_bidirectional_smpp_channel_with_custom_attributes,
      :account => account, :channel => channel
    )
  end

  let(:get_application) { create(:get_ack_application_with_url, :account => account) }
  let(:post_application) { create(:post_ack_application_with_url, :account => account) }

  include FakeWebHelpers

  def build_job(reference_application, options = {})
    options[:ao_message] ||= ao_message
    SendDeliveryAckJob.new(
      account.id, reference_application.id,
      options[:ao_message].id, options[:ao_message].state
    )
  end

  def do_job(reference_application, options = {})
    build_job(reference_application, options).perform
  end

  def setup_channel(reference_application, reference_channel)
    reference_channel.application = reference_application
    reference_channel.save!
  end

  describe "#perform" do
    context "for an application configured for GET acks" do
      context "with no auth" do
        before do
          setup_channel(get_application, channel)
          register_delivery_ack(:ao_message => ao_message)
        end

        it "should make a GET request for the delivery ack" do
          do_job(get_application)
          assert_delivery_ack(:get)
        end
      end

      context "with auth" do
        let(:application) { create(:get_ack_application_with_url_and_auth, :account => account) }

        before do
          setup_channel(application, channel)
          register_delivery_ack(:ao_message => ao_message)
        end

        it "should make a GET request for the delivery ack with auth" do
          do_job(application)
          assert_delivery_ack(:get)
        end
      end

      context "with custom attributes" do
        before do
          setup_channel(get_application, channel)
          register_delivery_ack(:ao_message => custom_attributes_ao_message)
        end

        it "should make a GET request for the delivery ack with the custom attributes" do
          do_job(get_application, :ao_message => custom_attributes_ao_message)
          assert_delivery_ack(:get)
        end
      end
    end

    context "for an application configured for POST acks" do
      context "with no auth" do
        before do
          setup_channel(post_application, channel)
          register_delivery_ack(:ao_message => ao_message)
        end

        it "should make a POST request for the delivery ack" do
          do_job(post_application)
          assert_delivery_ack(:post, :ao_message => ao_message)
        end
      end

      context "with auth" do
        let(:application) { create(:post_ack_application_with_url_and_auth, :account => account) }

        before do
          setup_channel(application, channel)
          register_delivery_ack(:ao_message => ao_message)
        end

        it "should make a POST request for the delivery ack with auth" do
          do_job(application)
          assert_delivery_ack(:post, :ao_message => ao_message)
        end
      end

      context "with custom attributes" do
        before do
          setup_channel(post_application, channel)
          register_delivery_ack(:ao_message => custom_attributes_ao_message)
        end

        it "should make a POST request for the delivery ack with the custom attributes" do
          do_job(post_application, :ao_message => custom_attributes_ao_message)
          assert_delivery_ack(:post, :ao_message => custom_attributes_ao_message)
        end
      end
    end

    context "POST" do
      before do
        setup_channel(post_application, channel)
      end

      # Retry if Unauthorized
      context "401 Unauthorized" do
        before do
          register_delivery_ack(:ao_message => ao_message, :status => ["401", "Unauthorized"])
        end

        it "should raise an error" do
          expect { do_job(post_application) }.to raise_error(
            "Sending HTTP delivery ack received unauthorized: invalid credentials"
          )
        end
      end

      # for Bad Requests don't retry
      context "400 Bad Request" do
        before do
          register_delivery_ack(:ao_message => ao_message, :status => ["400", "Bad Request"])
        end

        it "should catch the exception and log the result" do
          do_job(post_application)
          logs = Log.all
          logs.length.should == 1
          logs[0].message.should == "Received HTTP Bad Request (400) for delivery ack"
          logs[0].ao_message_id.should == ao_message.id
        end
      end
    end
  end

  describe "#reschedule" do
    let(:job) { build_job(post_application) }

    before do
      setup_channel(post_application, channel)
      register_delivery_ack(:ao_message => ao_message, :status => ["401", "Unauthorized"])
      begin
        job.perform
      rescue Exception => e
        job.reschedule(e)
      end
    end

    it "should reschedule the job" do
      scheduled_jobs = ScheduledJob.all
      scheduled_jobs.count.should == 1

      republished_job = scheduled_jobs.first.job.deserialize_job
      republished_job.should be_kind_of(RepublishApplicationJob)
      republished_job.application_id.should == post_application.id

      rescheduled_job = republished_job.job
      rescheduled_job.should be_kind_of(SendDeliveryAckJob)
      rescheduled_job.account_id.should == post_application.account_id
      rescheduled_job.application_id.should == post_application.id
      rescheduled_job.message_id.should == ao_message.id
      rescheduled_job.state.should == ao_message.state
      rescheduled_job.tries.should == 1
    end
  end
end
