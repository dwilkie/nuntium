require 'spec_helper'

describe Channel do
  describe "#switch_to_backup", :focus do
    def setup_channel(*args)
      create(:channel, :bidirectional, :with_application, *args)
    end

    def setup_application(*args)
      create(:application, :with_ao_rules, *args)
    end

    context "with no application ao_rules" do
      let(:channel) { setup_channel }

      it "should do nothing" do
        channel.switch_to_backup.should be_false
        channel.application.ao_rules.should be_nil
      end
    end

    context "with application ao rules" do
      let(:application_ao_rules) { application.reload.ao_rules }
      let(:channel) { setup_channel(:application => application, :name => "ch1") }

      def assert_channel_priority(priority, asserted_channel)
        application_ao_rules[priority]["actions"].first["value"].should == asserted_channel
      end

      context "and no backup channel" do
        let(:application) do
          setup_application(
            :suggested_channels => ActiveSupport::OrderedHash[
              "ch1", "match_criteria", "ch2", "different_match_criteria"
            ]
          )
        end

        it "should do nothing" do
          channel.switch_to_backup.should be_false
          assert_channel_priority(1, "ch1")
          assert_channel_priority(2, "ch2")
        end
      end

      context "and a backup channel" do
        context "where the current channel has the priority" do
          def setup_application(*args)
            super(*(args << {:suggested_channels => ActiveSupport::OrderedHash[
              "ch1", "match_criteria", "ch2", "match_criteria"
            ]}))
          end

          let(:application) { setup_application }

          context "backup has never been switched on" do
            it "should switch the priority to the backup channel" do
              channel.switch_to_backup.should be_true
              assert_channel_priority(1, "ch2")
              assert_channel_priority(2, "ch1")
            end
          end

          context "and the backup channel was recently prioritized" do
            let(:application) { setup_application(:recently_prioritized_backup_channel) }

            it "should do nothing" do
              channel.switch_to_backup.should be_false
              assert_channel_priority(1, "ch1")
              assert_channel_priority(2, "ch2")
            end
          end

          context "and the backup channel was not recently prioritized" do
            let(:application) do
              setup_application(:not_recently_prioritized_backup_channel)
            end

            context "passing no options" do

              it "should switch the priority to the backup channel" do
                channel.switch_to_backup.should be_true
                assert_channel_priority(1, "ch2")
                assert_channel_priority(2, "ch1")
              end
            end

            context "passing :timeout => 10.minutes" do
              it "should do nothing" do
                channel.switch_to_backup(:timeout => 10.minutes).should be_false
                assert_channel_priority(1, "ch1")
                assert_channel_priority(2, "ch2")
              end
            end
          end
        end

        context "where the backup channel already has the priority" do
          let(:application) do
            setup_application(
              :suggested_channels => ActiveSupport::OrderedHash[
                "ch2", "match_criteria", "ch1", "match_criteria"
              ]
            )
          end

          it "should do nothing" do
            channel.switch_to_backup.should be_false
            assert_channel_priority(1, "ch2")
            assert_channel_priority(2, "ch1")
          end
        end
      end
    end
  end
end
