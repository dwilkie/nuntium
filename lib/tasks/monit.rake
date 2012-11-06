require File.expand_path("../../../app/models/monit", __FILE__)

namespace :monit do
  desc "Creates the monit configuration for your environment"
  task :generate do
    path = Monit.generate_config!
    puts "wrote monit config for #{Rails.env} environment to #{path}"
  end

  desc "Alerts (via SMS or Email) if the Nuntium queues are overloaded"
  task :notify_queues_overloaded! => :environment do
    Monit.notify_queues_overloaded!
  end
end
