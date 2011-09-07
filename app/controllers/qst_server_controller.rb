class QstServerController < ApplicationController
  skip_filter :check_login

  before_filter :authenticate
  def authenticate
    authenticate_or_request_with_http_basic do |username, password|
      @account = Account.find_by_id_or_name params[:account_id]
      if @account
        @channel = @account.qst_server_channels.where(:name => username).first
        if @channel && @channel.authenticate(password)
          @channel.connected = true
          true
        else
          false
        end
      else
        false
      end
    end
  end

  before_filter :update_channel_last_activity_at
  def update_channel_last_activity_at
    @channel.last_activity_at = Time.now.utc
    @channel.save!
  end

  # HEAD /qst/:account_id/incoming
  def get_last_id
    return head(:not_found) unless request.head?
    msg = AtMessage.select(:guid).where(:account_id => @account.id, :channel_id => @channel.id).order(:timestamp).last
    etag = msg.nil? ? nil : msg.guid
    head :ok, 'Etag' => etag
  end

  # POST /qst/:account_id/incoming
  def push
    tree = request.POST.present? ? request.POST : Hash.from_xml(request.raw_post).with_indifferent_access

    last_id = nil
    AtMessage.parse_xml(tree) do |msg|
      @account.route_at msg, @channel
      last_id = msg.guid
    end

    head :ok, 'Etag' => last_id
  end

  # GET /qst/:account_id/outgoing
  def pull
    etag = request.env['HTTP_IF_NONE_MATCH']
    max = params[:max]

    # Default max to 10 if not specified
    max = max.nil? ? 10 : max.to_i

    # If there's an etag
    if !etag.nil?
      # Find the message by guid
      last = AoMessage.select('id').find_by_guid etag
      if !last.nil?
        # Mark messsages as delivered
        outs = @channel.qst_outgoing_messages.select(:ao_message_id).where 'ao_message_id <= ?', last.id
        outs.each do |out|
          AoMessage.where(:id => out.ao_message_id, :state => 'queued').update_all "state = 'delivered'"
        end

        # Delete previous messages in qst including it
        outs.delete_all
      end
    end

    # Loop while we have invalid messages
    begin
      # Read outgoing messages
      @ao_messages = nil

      # We need to do this query uncached in case we get back here in the loop
      # so as to not get the same messages again.
      ActiveRecord::Base.uncached do
        @ao_messages = AoMessage.
          joins('INNER JOIN qst_outgoing_messages ON ao_messages.id = qst_outgoing_messages.ao_message_id').
          order('qst_outgoing_messages.id').
          where("state = ? AND qst_outgoing_messages.channel_id = ?", 'queued', @channel.id).
          limit(max).all
      end

      if @ao_messages.present?
        # Separate messages into ones that have their tries
        # over max_tries and those still valid.
        valid_messages, invalid_messages = @ao_messages.partition { |msg| msg.tries < @account.max_tries }

        # Mark as failed messages that have their tries over max_tries
        if !invalid_messages.empty?
          invalid_messages.each do |invalid_message|
            AoMessage.where(:id => invalid_message.id).update_all "state = 'failed'"
            QstOutgoingMessage.where(:ao_message_id => invalid_message.id).delete_all
          end
          invalid_messages.each do |message|
            @account.logger.ao_message_delivery_exceeded_tries message, 'qst_server'
          end
        end
      end
    end until @ao_messages.empty? || invalid_messages.empty?

    # Update their number of retries and say that valid messages were returned
    @ao_messages.each do |message|
      AoMessage.where(:id => message.id).update_all 'tries = tries + 1'
      @account.logger.ao_message_delivery_succeeded message, 'qst_server'
    end

    @ao_messages.sort!{|x,y| x.timestamp <=> y.timestamp}

    response.headers['Etag'] = @ao_messages.last.id.to_s if @ao_messages.present?
    response.headers["Content-Type"] = "application/xml; charset=utf-8"
    render :text => AoMessage.write_xml(@ao_messages)
  end

  # GET /qst/:account_id/setaddress
  def set_address
    @channel.address = params[:address]
    @channel.save!
    head :ok
  end
end
