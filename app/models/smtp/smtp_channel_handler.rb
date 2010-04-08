require 'net/smtp'

class SmtpChannelHandler < ChannelHandler
  def handle(msg)
    Queues.publish_ao msg, create_job(msg)
  end
  
  def handle_now(msg)
    create_job(msg).perform
  end
  
  def create_job(msg)
    SendSmtpMessageJob.new(@channel.application_id, @channel.id, msg.id)
  end
  
  def check_valid
    check_config_not_blank :host, :user, :password
        
    if @channel.configuration[:port].nil?
      @channel.errors.add(:port, "can't be blank")
    else
      port_num = @channel.configuration[:port].to_i
      if port_num <= 0
        @channel.errors.add(:port, "must be a positive number")
      end
    end
  end
  
  def check_valid_in_ui
    config = @channel.configuration
    
    smtp = Net::SMTP.new(config[:host], config[:port].to_i)
    if (config[:use_ssl] == '1')
      smtp.enable_tls
    end
    
    begin
      smtp.start('localhost.localdomain', config[:user], config[:password])
      smtp.finish
    rescue => e
      @channel.errors.add_to_base(e.message)
    end
  end
  
  def on_enable
    Queues.bind_ao @channel
  end
  
  def info
    c = @channel.configuration
    "#{c[:user]}@#{c[:host]}:#{c[:port]}"
  end
end
