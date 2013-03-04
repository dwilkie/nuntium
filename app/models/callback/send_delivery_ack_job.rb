class SendDeliveryAckJob
  attr_accessor :account_id, :application_id, :message_id, :state, :tries

  def initialize(account_id, application_id, message_id, state, tries = 0)
    @account_id = account_id
    @application_id = application_id
    @message_id = message_id
    @state = state
    @tries = tries
  end

  def perform
    @account = Account.find_by_id @account_id
    @app = @account.applications.find_by_id @application_id
    @msg = AoMessage.get_message @message_id
    @chan = @account.channels.find_by_id @msg.channel_id

    return unless @app and @chan and @app.delivery_ack_method != 'none'

    data = {
      :guid => @msg.guid, :channel => @chan.name, :state => @state
    }

    data.merge!(:token => @msg.token) if @msg.token
    data.merge!(@msg.custom_attributes)

    options = {:headers => {:content_type => "application/x-www-form-urlencoded"}}
    if @app.delivery_ack_user.present?
      options[:user] = @app.delivery_ack_user
      options[:password] = @app.delivery_ack_password
    end

    res = RestClient::Resource.new @app.delivery_ack_url, options

    begin
      @app.delivery_ack_method == 'get' ? res["?#{data.to_query}"].get : res.post(data)
      @app.logger.info :ao_message_id => @message_id, :message => "Successfully posted delivery receipt"
    rescue RestClient::Unauthorized
      alert_msg = "Sending HTTP delivery ack received unauthorized: invalid credentials"
      @app.alert alert_msg
      raise alert_msg
    rescue RestClient::BadRequest
      @app.logger.warning :ao_message_id => @message_id, :message => "Received HTTP Bad Request (400) for delivery ack"
    end
  end

  def reschedule(ex)
    @app.logger.warning :ao_message_id => @message_id, :message => ex.message

    tries = self.tries + 1
    new_job = self.class.new(@account_id, @application_id, @message_id, @state, tries)
    ScheduledJob.create! :job => RepublishApplicationJob.new(@application_id, new_job), :run_at => tries.as_exponential_backoff.minutes.from_now
  end
end
