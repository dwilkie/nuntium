FakeWeb.allow_net_connect = false

module FakeWebHelpers

  def last_request
    FakeWeb.last_request
  end

  def register_delivery_ack(options = {})
    ao_message = options[:ao_message]
    channel = ao_message.channel
    application = channel.application
    method = options[:method] || application.delivery_ack_method
    url = options[:endpoint] || application.delivery_ack_url
    status = options[:status] || ["200", "OK"]

    uri = URI.parse(url)
    uri.path = "/" if uri.path.empty?
    uri.query = "channel=#{channel.name}&guid=#{ao_message.guid}&state=#{ao_message.state}"

    FakeWeb.register_uri(
      method.to_sym, uri.to_s, :body => options[:body], :status => status
    )
  end
end
