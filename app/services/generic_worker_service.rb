class GenericWorkerService < Service
  
  def initialize(controller = nil, suspension_time = 5 * 60)
    super(controller)
    @suspension_time = suspension_time
  end

  def start
    @sessions = {}
    
    Channel.find_each(
      :conditions => ['enabled = ? AND (direction = ? OR direction = ?)', 
        true, 
        Channel::Outgoing, Channel::Both]) do |chan|
      next unless chan.handler.class < GenericChannelHandler
      
      mq = MQ.new
      @sessions[chan.id] = mq

      Queues.subscribe_ao chan, mq do |header, job|
        begin
          job.perform
        rescue PermanentException => ex
          chan.enabled = false
          chan.save!
        rescue TemporaryException => ex
          Queues.publish_notification ChannelUnsubscriptionJob.new(chan), @notifications_session
          EM.add_timer(@suspension_time) do 
            Queues.publish_notification ChannelSubscriptionJob.new(chan), @notifications_session            
          end
        end
      end
    end
    
    @notifications_session = MQ.new
    Queues.subscribe_notifications @notifications_session do |header, job|
    end
  end
  
  def stop
  end

end
