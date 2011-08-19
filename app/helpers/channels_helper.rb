module ChannelsHelper
  def form_for_channel(channel, &block)
    form_for channel.becomes(Channel), :url => (channel.new_record? ? channels_path : channel_path(channel)), &block
  end
end
