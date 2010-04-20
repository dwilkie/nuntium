class SmppChannelHandler < ChannelHandler
  def handle(msg)
    Queues.publish_ao msg, create_job(msg)
  end
  
  def handle_now(msg)
    handle msg
  end
  
  def create_job(msg)
    SendSmppMessageJob.new(@channel.account_id, @channel.id, msg.id)
  end
  
  def on_enable
    ManagedProcess.create!(
      :account_id => @channel.account.id,
      :name => managed_process_name,
      :start_command => "smpp_daemon_ctl.rb start -- #{ENV["RAILS_ENV"]} #{@channel.id}",
      :stop_command => "smpp_daemon_ctl.rb stop -- #{ENV["RAILS_ENV"]} #{@channel.id}",
      :pid_file => "smpp_daemon.#{@channel.id}.pid",
      :log_file => "smpp_daemon_#{@channel.id}.log",
      :enabled => true
    )
    Queues.bind_ao @channel
  end
  
  def on_disable
    proc = ManagedProcess.find_by_account_id_and_name @channel.account.id, managed_process_name
    proc.destroy if proc
  end
  
  def on_changed
    proc = ManagedProcess.find_by_account_id_and_name @channel.account.id, managed_process_name
    proc.touch if proc
  end
  
  def on_destroy
    on_disable
  end
  
  def managed_process_name
    "SMPP #{@channel.name}"
  end
  
  def check_valid
    check_config_not_blank :host, :system_type
    
    if @channel.configuration[:port].nil?
      @channel.errors.add(:port, "can't be blank")
    else
      port_num = @channel.configuration[:port].to_i
      if port_num <= 0
        @channel.errors.add(:port, "must be a positive number")
      end
    end
    
    [:source_ton, :source_npi, :destination_ton, :destination_npi].each do |sym|
      if @channel.configuration[sym].nil?
        @channel.errors.add(sym, "can't be blank")
      else
        s = @channel.configuration[sym].to_i
        if s < 0 || s > 7
          @channel.errors.add(sym, "must be a number between 0 and 7")
        end
      end
    end
  
    check_config_not_blank :user, :password, :default_mo_encoding, :mt_encodings, :mt_csms_method
  end
  
  def check_valid_in_ui
    config = @channel.configuration
    
    # what kind of validation should we put here?
    # what if the smpp connection require a vpn?

  end
  
  def info
    c = @channel.configuration
    "#{c[:user]}@#{c[:host]}:#{c[:port]}"
  end
end
