require 'test_helper'

class ApiTwitterChannelControllerTest < ActionController::TestCase
  [nil, false, true].each do |follow|
    test "account authenticated with follow #{follow}" do
      @account = Account.make :password => 'secret'
      @channel = TwitterChannel.make :account => @account

      client = mock('client')
      client.expects(:friendship_exists?).with('foo', @channel.configuration[:screen_name]).returns(false)
      client.expects(:friendship_create).with('foo', follow.to_b)

      TwitterChannel.expects(:new_client).with(@channel.configuration).returns(client)

      @request.env['HTTP_AUTHORIZATION'] = http_auth(@account.name, 'secret')
      get :friendship_create, :name => @channel.name, :user => 'foo', :follow => follow

      assert_response :ok
    end
  end

  test "application authenticated" do
    @account = Account.make :password => 'secret'
    @application = Application.make :account => @account, :password => 'secret2'
    @channel = TwitterChannel.make :account => @account, :application => @application

    client = mock('client')
    client.expects(:friendship_exists?).with('foo', @channel.configuration[:screen_name]).returns(false)
    client.expects(:friendship_create).with('foo', false)

    TwitterChannel.expects(:new_client).with(@channel.configuration).returns(client)

    @request.env['HTTP_AUTHORIZATION'] = http_auth("#{@account.name}/#{@application.name}", 'secret2')
    get :friendship_create, :name => @channel.name, :user => 'foo'

    assert_response :ok
  end

  test "application authenticated already following" do
    @account = Account.make :password => 'secret'
    @application = Application.make :account => @account, :password => 'secret2'
    @channel = TwitterChannel.make :account => @account, :application => @application

    client = mock('client')
    client.expects(:friendship_exists?).with('foo', @channel.configuration[:screen_name]).returns(true)
    client.expects(:friendship_create).never

    TwitterChannel.expects(:new_client).with(@channel.configuration).returns(client)

    @request.env['HTTP_AUTHORIZATION'] = http_auth("#{@account.name}/#{@application.name}", 'secret2')
    get :friendship_create, :name => @channel.name, :user => 'foo'

    assert_response :ok
  end

  test "application authenticated can't access account channel" do
    @account = Account.make :password => 'secret'
    @application = Application.make :account => @account, :password => 'secret2'
    @channel = TwitterChannel.make :account => @account

    @request.env['HTTP_AUTHORIZATION'] = http_auth("#{@account.name}/#{@application.name}", 'secret2')
    get :friendship_create, :name => @channel.name, :user => 'foo'

    assert_response :forbidden
  end

  test "channel not found" do
    @account = Account.make :password => 'secret'

    @request.env['HTTP_AUTHORIZATION'] = http_auth(@account.name, 'secret')
    get :friendship_create, :name => 'not_exists', :user => 'foo'

    assert_response :not_found
  end

  test "channel not twitter" do
    @account = Account.make :password => 'secret'
    @channel = QstServerChannel.make :account => @account

    @request.env['HTTP_AUTHORIZATION'] = http_auth(@account.name, 'secret')
    get :friendship_create, :name => @channel.name, :user => 'foo'

    assert_response :bad_request
  end

  [Twitter::General, Twitter::NotFound, Twitter::InformTwitter, Twitter::Unavailable].each do |ex|
    test "twitter error #{ex}" do
      @account = Account.make :password => 'secret'
      @channel = TwitterChannel.make :account => @account

      client = mock('client')
      client.expects(:friendship_exists?).with('foo', @channel.configuration[:screen_name]).returns(false)
      client.expects(:friendship_create).with('foo', true).raises(ex.new('foo'), '(403): Forbidden - Could not follow user: foo is already on your list')

      TwitterChannel.expects(:new_client).with(@channel.configuration).returns(client)

      @request.env['HTTP_AUTHORIZATION'] = http_auth(@account.name, 'secret')
      get :friendship_create, :name => @channel.name, :user => 'foo', :follow => true

      assert_response 403
      assert_equal 'Forbidden - Could not follow user: foo is already on your list', @response.body
    end
  end
end
