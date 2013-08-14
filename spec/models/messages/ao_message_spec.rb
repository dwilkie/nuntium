require 'spec_helper'

describe AoMessage do
  let(:account) { create(:account, :max_tries => 3) }
  let(:channel) { create_channel }

  def create_channel(attributes = {})
    create(:channel, :bidirectional, {:account => account}.merge(attributes))
  end

  def create_ao_message(attributes = {})
    create(:ao_message, {:account => account, :channel => channel}.merge(attributes))
  end

  subject { create_ao_message }

  describe "callbacks" do
    describe "before_save" do
      describe "routing to failover" do
        context "given the message failed" do

          let(:failover_channel) { create(:channel, :bidirectional, :account => account) }

          before do
            subject.state = "failed"
            account.stub_chain(:channels, :find_by_name)
            account.stub_chain(:channels, :find_by_name).with(failover_channel.name).and_return(failover_channel)
            account.stub_chain(:channels, :find_by_id).with(failover_channel.id.to_s).and_return(failover_channel)
          end

          shared_examples_for "not re-routing the AO" do
            it "should not re-route the AO" do
              failover_channel.should_not_receive(:route_ao)
              subject.save!
            end
          end

          shared_examples_for "re-routing the AO" do
            it "should re-route the AO through the failover channel" do
              failover_channel.should_receive(:route_ao).with(subject, 're-route', :dont_save => true)
              subject.save!
            end
          end

          context "and no explicit failover channel is available" do
            it_should_behave_like "not re-routing the AO"
          end

          context "and no implicit failover channel is available" do
            let(:channel) { create_channel(:name => "smart") }
            let(:failover_channel) { create_channel(:name => "smart3") }

            it_should_behave_like "not re-routing the AO"
          end

          context "and a failover channel is available" do
            context "set explicitly" do
              def create_ao_message(attributes = {})
                super({:failover_channels => failover_channel.id.to_s}.merge(attributes))
              end

              subject { create_ao_message }
              it_should_behave_like "re-routing the AO"

              context "max_tries has been reached for this AO" do
                subject { create_ao_message(:tries => account.max_tries) }
                it_should_behave_like "not re-routing the AO"
              end
            end

            context "set implictly by the channel name" do
              context "where the main channel failed" do
                let(:channel) { create_channel(:name => "smart") }
                let(:failover_channel) { create_channel(:name => "smart2") }

                it_should_behave_like "re-routing the AO"
              end

              context "where the failover channel failed" do
                let(:channel) { create_channel(:name => "smart2") }
                let(:failover_channel) { create_channel(:name => "smart") }

                it_should_behave_like "re-routing the AO"
              end
            end
          end
        end
      end
    end
  end
end
