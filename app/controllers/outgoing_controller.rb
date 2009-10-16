class OutgoingController < ApplicationController
  # GET /qst/outgoing
  def index
    last_modified = request.env['If-Modified-Since']
    etag = request.env['If-None-Match']
    
    if last_modified.nil?
      @out_messages = OutMessage.all(:order => 'timestamp DESC')
    else
      @out_messages = OutMessage.all(:order => 'timestamp DESC', :conditions => ['timestamp > ?', DateTime.parse(last_modified)])
      if @out_messages.length == 0
        head :not_modified
      end
    end
    
    if !etag.nil?
      temp_messages = []
      @out_messages.each do |msg|
        if msg.guid == etag
          break
        end
        temp_messages.push msg
      end
      
      if temp_messages.length == 0
        head :not_modified
      else
        @out_messages = temp_messages
      end
    end
  end
end
