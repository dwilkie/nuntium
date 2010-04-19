require 'test_helper'

class MessageControllerTest < ActionController::TestCase

  test "mark ao messages as cancelled" do
    app = Application.create!({:name => 'app', :password => 'app_pass'})
    msg1 = AOMessage.create!(:application_id => app.id, :state => 'queued')
    msg2 = AOMessage.create!(:application_id => app.id, :state => 'queued')
    msg3 = AOMessage.create!(:application_id => app.id, :state => 'queued')
    
    get :mark_ao_messages_as_cancelled, {:ao_messages => [msg1.id, msg2.id]}, {:application_id => app.id}
    
    assert_redirected_to(:controller => 'home', :action => 'home', :ao_messages => [msg1.id, msg2.id])
    assert_equal '2 Application Originated messages were marked as cancelled', flash[:notice]
    
    msgs = AOMessage.all
    assert_equal 'cancelled', msgs[0].state
    assert_equal 'cancelled', msgs[1].state
    assert_equal 'queued', msgs[2].state
  end
  
  test "mark ao messages as cancelled using search" do
    app = Application.create!({:name => 'app', :password => 'app_pass'})
    msg1 = AOMessage.create!(:application_id => app.id, :state => 'queued', :body => 'one')
    msg2 = AOMessage.create!(:application_id => app.id, :state => 'queued', :body => 'one')
    msg3 = AOMessage.create!(:application_id => app.id, :state => 'queued', :body => 'two')
    
    get :mark_ao_messages_as_cancelled, {:ao_all => 1, :ao_search => 'one'}, {:application_id => app.id}
    
    assert_redirected_to(:controller => 'home', :action => 'home', :ao_all => 1, :ao_search => 'one')
    assert_equal '2 Application Originated messages were marked as cancelled', flash[:notice]
    
    msgs = AOMessage.all
    assert_equal 'cancelled', msgs[0].state
    assert_equal 'cancelled', msgs[1].state
    assert_equal 'queued', msgs[2].state
  end
  
  test "mark at messages as cancelled" do
    app = Application.create!({:name => 'app', :password => 'app_pass'})
    msg1 = ATMessage.create!(:application_id => app.id, :state => 'queued')
    msg2 = ATMessage.create!(:application_id => app.id, :state => 'queued')
    msg3 = ATMessage.create!(:application_id => app.id, :state => 'queued')
    
    get :mark_at_messages_as_cancelled, {:at_messages => [msg1.id, msg2.id]}, {:application_id => app.id}
    
    assert_redirected_to(:controller => 'home', :action => 'home', :at_messages => [msg1.id, msg2.id])
    assert_equal '2 Application Terminated messages were marked as cancelled', flash[:notice]
    
    msgs = ATMessage.all
    assert_equal 'cancelled', msgs[0].state
    assert_equal 'cancelled', msgs[1].state
    assert_equal 'queued', msgs[2].state
  end
  
  test "mark at messages as cancelled using search" do
    app = Application.create!({:name => 'app', :password => 'app_pass'})
    msg1 = ATMessage.create!(:application_id => app.id, :state => 'queued', :body => 'one')
    msg2 = ATMessage.create!(:application_id => app.id, :state => 'queued', :body => 'one')
    msg3 = ATMessage.create!(:application_id => app.id, :state => 'queued', :body => 'two')
    
    get :mark_at_messages_as_cancelled, {:at_all => 1, :at_search => 'one'}, {:application_id => app.id}
    
    assert_redirected_to(:controller => 'home', :action => 'home', :at_all => 1, :at_search => 'one')
    assert_equal '2 Application Terminated messages were marked as cancelled', flash[:notice]
    
    msgs = ATMessage.all
    assert_equal 'cancelled', msgs[0].state
    assert_equal 'cancelled', msgs[1].state
    assert_equal 'queued', msgs[2].state
  end
  
  test "re-route ao messages" do
    app = Application.create!({:name => 'app', :password => 'app_pass'})
    msg1 = AOMessage.create!(:application_id => app.id, :state => 'pending', :to => 'sms://1234', :tries => 3)
    msg2 = AOMessage.create!(:application_id => app.id, :state => 'pending', :to => 'sms://1234', :tries => 3)
    msg3 = AOMessage.create!(:application_id => app.id, :state => 'pending', :to => 'sms://1234', :tries => 3)
    
    new_channel app, 'foo'
    
    get :reroute_ao_messages, {:ao_messages => [msg1.id, msg2.id]}, {:application_id => app.id}
    
    assert_redirected_to(:controller => 'home', :action => 'home', :ao_messages => [msg1.id, msg2.id])
    assert_equal '2 Application Originated messages were re-routed', flash[:notice]
    
    msgs = AOMessage.all
    assert_equal 'queued', msgs[0].state
    assert_equal 'queued', msgs[1].state
    assert_equal 'pending', msgs[2].state
    
    assert_equal 0, msgs[0].tries
    assert_equal 0, msgs[1].tries
    assert_equal 3, msgs[2].tries
  end
  
  test "re-route ao messages using search" do
    app = Application.create!({:name => 'app', :password => 'app_pass'})
    msg1 = AOMessage.create!(:application_id => app.id, :state => 'pending', :body => 'one', :to => 'sms://1234', :tries => 3)
    msg2 = AOMessage.create!(:application_id => app.id, :state => 'pending', :body => 'one', :to => 'sms://1234', :tries => 3)
    msg3 = AOMessage.create!(:application_id => app.id, :state => 'pending', :body => 'two', :to => 'sms://1234', :tries => 3)
    
    new_channel app, 'foo'
    
    get :reroute_ao_messages, {:ao_all => 1, :ao_search => 'one'}, {:application_id => app.id}
    
    assert_redirected_to(:controller => 'home', :action => 'home', :ao_all => 1, :ao_search => 'one')
    assert_equal '2 Application Originated messages were re-routed', flash[:notice]
    
    msgs = AOMessage.all
    assert_equal 'queued', msgs[0].state
    assert_equal 'queued', msgs[1].state
    assert_equal 'pending', msgs[2].state
    
    assert_equal 0, msgs[0].tries
    assert_equal 0, msgs[1].tries
    assert_equal 3, msgs[2].tries
  end
  
  def new_channel(app, name)
    chan = Channel.new(:application_id => app.id, :name => name, :kind => 'qst_server', :protocol => 'sms', :direction => Channel::Bidirectional);
    chan.configuration = {:url => 'a', :user => 'b', :password => 'c'};
    chan.save!
    chan
  end

end
