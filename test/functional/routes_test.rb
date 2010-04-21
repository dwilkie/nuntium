require 'test_helper'

class RoutesTest < ActionController::TestCase
  test "routes" do
    assert_routing({:path => "/rss", :method => :get }, { :controller => "rss", :action => "index" })
    assert_routing({:path => "/rss", :method => :post }, { :controller => "rss", :action => "create" })
    assert_routing({:path => "/qst/some_account/incoming", :method => :head }, { :controller => "incoming", :action => "index", :account_id => "some_account" })
    assert_routing({:path => "/qst/some_account/incoming", :method => :post }, { :controller => "incoming", :action => "create", :account_id => "some_account" })
    assert_routing({:path => "/qst/some_account/outgoing", :method => :get }, { :controller => "outgoing", :action => "index", :account_id => "some_account" })
    ["create_account", "login", "logoff"].each do |path|
      assert_routing({:path => "/" + path}, { :controller => "home", :action => path })
    end
    ["edit", "update"].each do |op|
      assert_routing({:path => "/account/#{op}"}, { :controller => "home", :action => "#{op}_account"})
    end
    assert_routing({:path => "/account/alerts/edit"}, { :controller => "home", :action => "edit_account_alerts"})
    assert_routing({:path => "/account/alerts/update"}, { :controller => "home", :action => "update_account_alerts"})
    assert_routing({:path => "/account/find_address_source"}, { :controller => "home", :action => "find_address_source"})
    assert_routing({:path => "/account/failed_alerts/delete"}, { :controller => "home", :action => "delete_failed_alerts"})
    assert_routing({:path => "/channel/create/twitter"}, { :controller => "twitter", :action => "create_twitter_channel", :kind => "twitter" })
    assert_routing({:path => "/channel/update/twitter"}, { :controller => "twitter", :action => "update_twitter_channel" })
    assert_routing({:path => "/twitter_callback"}, { :controller => "twitter", :action => "twitter_callback" })
    ["new", "create"].each do |op|
      assert_routing({:path => "/channel/#{op}/qst_server"}, { :controller => "channel", :action => "#{op}_channel", :kind => 'qst_server' })
    end
    ["edit", "update", "delete", "enable", "disable"].each do |op|
      assert_routing({:path => "/channel/#{op}/10"}, { :controller => "channel", :action => "#{op}_channel", :id => '10' })
    end
    ["ao", "at"].each do |kind|
      ["new", "create"].each do |op|
        assert_routing({:path => "/message/#{kind}/#{op}"}, { :controller => "message", :action => "#{op}_#{kind}_message" })
      end
      assert_routing({:path => "/message/#{kind}/mark_as_cancelled"}, { :controller => "message", :action => "mark_#{kind}_messages_as_cancelled" })
      assert_routing({:path => "/message/#{kind}/10"}, { :controller => "message", :action => "view_#{kind}_message", :id => '10' })
    end
    assert_routing({:path => "/message/ao/reroute"}, { :controller => "message", :action => "reroute_ao_messages" })
    assert_routing({:path => "/send_ao"}, { :controller => "send_ao", :action => "create" })
  end
end
