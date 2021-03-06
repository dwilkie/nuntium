require 'twitter'

class TwitterController < ChannelsController
  include CustomAttributesControllerCommon
  include RulesControllerCommon

  before_filter :set_channel_parameters, :only => [:create, :update]
  before_filter :check_twitter_properly_configured

  def create
    if channel.save
      go_to_twitter
    else
      render "channels/new"
    end
  end

  def update
    if channel.save
      go_to_twitter
    else
      render "channels/edit"
    end
  end

  def callback
    oauth = TwitterChannel.new_oauth
    oauth.authorize_from_request(session['twitter_token'], session['twitter_secret'], params[:oauth_verifier])
    profile = Twitter::Base.new(oauth).verify_credentials
    access_token = oauth.access_token

    @channel = Channel.find session['twitter_channel_id']
    @update = !@channel.new_record?

    @channel.screen_name = profile.screen_name
    @channel.token = access_token.token
    @channel.secret = access_token.secret

    session['twitter_token']  = nil
    session['twitter_secret'] = nil
    session['twitter_channel_id'] = nil

    if @channel.save
      flash[:notice] = @update ? "Channel #{@channel.name} was updated" : "Channel #{@channel.name} was created"
    else
      flash[:notice] = "Channel #{@channel.name} couldn't be saved"
    end
    redirect_to channels_path
  end

  def view_rate_limit_status
    id = params[:id]
    @channel = @account.channels.find_by_id id
    if @channel.nil? || @channel.account_id != @account.id || @channel.kind != 'twitter'
      return redirect_to_home
    end

    render :text => @channel.get_rate_limit_status
  end

  protected

  def go_to_twitter
    oauth = TwitterChannel.new_oauth

    request_token = oauth.request_token

    session['twitter_token'] = request_token.token
    session['twitter_secret'] = request_token.secret
    session['twitter_channel_id'] = channel.id

    redirect_to request_token.authorize_url
  end

  def check_twitter_properly_configured
    return redirect_to_home if Nuntium::TwitterConsumerConfig.nil?
  end
end
