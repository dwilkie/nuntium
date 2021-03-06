class ReceiveMultimodemIsmsMessageJob

  attr_accessor :account_id, :channel_id

  include CronTask::QuotedTask

  def initialize(account_id, channel_id)
    @account_id = account_id
    @channel_id = channel_id
  end

  def perform
    account = Account.find @account_id
    @channel = account.channels.find_by_id @channel_id
    @config = @channel.configuration

    url = "http://#{@config[:host]}"
    url << ":#{@config[:port]}" if @config[:port].present?
    url << "/recvmsg?"
    url << "user=#{CGI.escape(@config[:user])}&"
    url << "passwd=#{CGI.escape(@config[:password])}"

    response = RestClient.get url
    response = Hash.from_xml response.body
    notifs = response['Response']['MessageNotification']
    return unless notifs

    notifs = [notifs] unless notifs.kind_of? Array
    notifs.each do |notif|
      msg = AtMessage.new

      from = notif['SenderNumber'] || ''
      from = from[1 .. -1] if from.start_with? '+'
      msg.from = from.with_protocol @channel.protocol

      modem = notif['ModemNumber'] || ''
      index = modem.index ':'
      modem = modem[index + 1 .. -1] if index
      modem = modem[1 .. -1] if modem.start_with? '+'
      msg.to = modem.with_protocol @channel.protocol

      msg.body = CGI.unescape notif['Message']

      begin
        date = notif['Date'].split '/'
        date[0], date[1], date[2] = date[2], date[1], date[0]
        date = date.join '-'
        date << " #{notif['Time']}"
        msg.timestamp = ActiveSupport::TimeZone[@config[:time_zone]].parse date
      rescue => e
      end
      account.route_at msg, @channel
    end
  rescue => ex
    p ex
    AccountLogger.exception_in_channel @channel, ex if @channel
  end

end
