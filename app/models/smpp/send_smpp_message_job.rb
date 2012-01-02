class SendSmppMessageJob
  include ReschedulableSendMessageJob

  attr_accessor :account_id, :channel_id, :message_id

  def initialize(account_id, channel_id, message_id)
    @account_id = account_id
    @channel_id = channel_id
    @message_id = message_id
  end

  def perform(delegate)
    @msg = AoMessage.find @message_id

    return true if @msg.channel_id != @channel_id
    return true if @msg.state != 'queued'

    @account = Account.find_by_id @account_id
    @channel = @account.channels.find_by_id @channel_id

    from = @msg.from.protocol == 'sms' ? @msg.from.without_protocol : @channel.address.without_protocol
    to = @msg.to.without_protocol
    sms = @msg.subject_and_body

    options = {}
    @msg.custom_attributes.each do |key, value|
      option_key =
        if key =~ /^smpp_0x([\da-fA-F]+)$/
          $1.to_i(16)
        elsif key =~ /^smpp_(\d+)$/
          $1.to_i
        end
      if option_key
        options[option_key] = value
      end
    end

    error = delegate.send_message(@msg.id, from, to, sms, options)
    if error
      @msg.send_failed @account, @channel, error
      false
    else
      true
    end
  rescue Exception => ex
    @msg.tries += 1
    @msg.save!
    raise ex
  end

  def to_s
    "<SendSmppMessageJob:#{@message_id}>"
  end
end
