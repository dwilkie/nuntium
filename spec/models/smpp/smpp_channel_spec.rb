require 'spec_helper'

describe SmppChannel do
  subject { build(:smpp_channel, :bidirectional) }

  describe "#bind_type" do
    it "should be a configuration accessor" do
      subject.bind_type = "transmitter"
      subject.save!
      subject.reload
      subject.bind_type.should == "transmitter"
    end
  end

  describe "#csms_transmission" do
    it "should be a configuration accessor" do
      subject.csms_transmission = "auto"
      subject.save!
      subject.reload
      subject.csms_transmission.should == "auto"
    end
  end
end
