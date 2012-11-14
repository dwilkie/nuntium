FakeWeb.allow_net_connect = false

module FakeWebHelpers

  def last_request
    FakeWeb.last_request
  end

  def register_delivery_ack(options = {})
    options[:channel] ||= options[:ao_message].channel
    options[:application] ||= options[:channel].application
    options[:method] ||= options[:application].delivery_ack_method.try(:to_sym)
    options[:endpoint] ||= options[:application].delivery_ack_url
    options[:status] ||= ["200", "OK"]
    options[:user] ||= options[:application].delivery_ack_user
    options[:password] ||= options[:application].delivery_ack_password
    options[:custom_attributes] ||= options[:ao_message].custom_attributes

    uri = URI.parse(options[:endpoint])
    uri.user = options[:user] if options[:user]
    uri.password = options[:password] if options[:password]
    uri.path = "/" if uri.path.empty?

    uri.query = Rack::Utils.build_query(build_ack_query(options)) if options[:method] == :get

    FakeWeb.register_uri(
      options[:method], uri.to_s, :body => options[:body], :status => options[:status]
    )
  end

  def assert_delivery_ack(method, options = {})
    last_request.method.should == method.to_s.upcase
    if method == :post
      Rack::Utils.parse_query(last_request.body).should == build_ack_query(options)
    end
  end

  private

  def build_ack_query(options = {})
    options[:channel] ||= options[:ao_message].channel
    {
      "channel" => options[:channel].name,
      "guid" => options[:ao_message].guid,
      "state" => options[:ao_message].state
    }.merge(options[:ao_message].custom_attributes)
  end
end
