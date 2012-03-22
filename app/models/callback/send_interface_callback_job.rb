require 'rest_client'

class SendInterfaceCallbackJob
  attr_accessor :account_id, :application_id, :message_id, :tries

  def initialize(account_id, application_id, message_id, tries = 0)
    @account_id = account_id
    @application_id = application_id
    @message_id = message_id
    @tries = tries
  end

  def perform
    @account = Account.find_by_id @account_id
    @app = @account.applications.find_by_id @application_id
    @msg = AtMessage.get_message @message_id
    return if @msg.nil? || @msg.state != 'queued'

    @msg.tries += 1
    @msg.save!

    content_type = "application/x-www-form-urlencoded"

    if @app.interface_custom_format.present?
      looks_like_xml = looks_like_xml?(@app.interface_custom_format)
      if @app.interface == 'http_post_callback' && looks_like_xml
        content_type = 'application/xml'
      end
      data = apply_custom_format @msg, @app, looks_like_xml
    else
      data = {
        :application => @app.name,
        :from => @msg.from,
        :to => @msg.to,
        :subject => @msg.subject.try(:sanitize),
        :body => @msg.body.try(:sanitize),
        :guid => @msg.guid,
        :channel => @msg.channel.try(:name)
      }.merge(@msg.custom_attributes)
      data = data.to_query if @app.interface == 'http_get_callback'
    end

    options = {:headers => {:content_type => content_type}}
    if @app.interface_user.present?
      options[:user] = @app.interface_user
      options[:password] = @app.interface_password
    end

    http_method = @app.interface == 'http_get_callback' ? 'GET' : 'POST'

    @app.logger.info :at_message_id => @msg.id, :channel_id => @msg.channel.try(:id), :message => "Executing #{http_method} callback to #{@app.interface_url}"

    begin
      res = RestClient::Resource.new(@app.interface_url, options)
      res = @app.interface == 'http_get_callback' ? res["?#{data}"].get : res.post(data)
      netres = res.net_http_res

      case netres
        when Net::HTTPSuccess, Net::HTTPRedirection
          @msg.state = 'delivered'
          @msg.save!

          AtMessage.log_delivery([@msg], @account, "http #{http_method.downcase} callback")

          # If the response includes a body, create an AO message from it
          if res.body.present?
            case netres.content_type
            when 'application/json'
              @app.logger.info :at_message_id => @msg.id, :channel_id => @msg.channel.try(:id), :message => "#{http_method} callback returned JSON: routed as AO messages"

              hashes = JSON.parse(res.body)
              hashes = [hashes] unless hashes.is_a? Array
              hashes.each do |hash|
                parsed = AoMessage.from_hash hash
                parsed.token ||= @msg.token
                @app.route_ao parsed, "http #{http_method.downcase} callback"
              end
            when 'application/xml'
              @app.logger.info :at_message_id => @msg.id, :channel_id => @msg.channel.try(:id), :message => "#{http_method} callback returned XML: routed as AO messages"

              AoMessage.parse_xml(res.body) do |parsed|
                parsed.token ||= @msg.token
                @app.route_ao parsed, "http #{http_method.downcase} callback"
              end
            else
              @app.logger.info :at_message_id => @msg.id, :channel_id => @msg.channel.try(:id), :message => "#{http_method} callback returned text: routed an AO message reply"
              reply = @msg.new_reply res.body
              reply.token = @msg.token
              @app.route_ao reply, "http #{http_method.downcase} callback"
            end
          end
        when Net::HTTPUnauthorized
          alert_msg = "#{http_method} callback to #{@app.interface_url} received unauthorized: invalid credentials"
          @app.alert alert_msg
          raise alert_msg
        else
          raise "HTTP #{http_method} callback failed #{netres.error!}"
      end
    rescue RestClient::BadRequest
      @msg.send_failed @account, @app, "Received HTTP Bad Request (404)"
    rescue => ex
      @msg.send_failed @account, @app, "#{http_method} callback failed: #{ex.message}"
      raise ex
    end
  end

  def reschedule(ex)
    @msg.state = 'delayed'
    @msg.save!

    @app.logger.warning :at_message_id => @message_id, :message => ex.message

    tries = self.tries + 1
    new_job = self.class.new(@account_id, @application_id, @message_id, tries)
    ScheduledJob.create! :job => RepublishAtJob.new(@application_id, @message_id, new_job), :run_at => tries.as_exponential_backoff.minutes.from_now
  end

  def to_s
    "<SendInterfaceCallbackJob:#{@message_id}>"
  end

  private

  def apply_custom_format(msg, app, looks_like_xml)
    escape = app.interface == 'http_get_callback'
    app.interface_custom_format.gsub(%r(\$\{(.*?)\})) do |match|
      # Remove the ${ from the beginning and the } from the end
      match = match[2 .. -2]
      if MessageCommon::Fields.include? match
        match = msg.send match
      elsif match == 'from_without_protocol'
        match = msg.from.try(:without_protocol)
      elsif match == 'to_without_protocol'
        match = msg.to.try(:without_protocol)
      elsif match == 'subject_and_body'
        match = msg.subject_and_body
      elsif match == 'channel'
        match = msg.channel.name
      elsif match == 'application'
        match = app.name
      else
        match = msg.custom_attributes[match]
      end
      match ||= ''
      if looks_like_xml
        match = match.to_xs
      elsif escape
        match = CGI.escape(match || '')
      end
      match
    end
  end

  def looks_like_xml?(string)
    string =~ %r(</(.*?)>) && %r(<#{$1})
  end
end
