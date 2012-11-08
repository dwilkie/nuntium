require File.expand_path("../../../app/models/monit", __FILE__)

namespace :monit do
  desc "Creates the monit configuration for your environment"
  task :generate do
    path = Monit.generate_config!
    puts "wrote monit config for #{Rails.env} environment to #{path}"
  end

  desc "Alerts (via SMS or Email) if the monit queues are overloaded"
  task :notify_queues_overloaded do
    Rake::Task["monit:notify_queues_overloaded!"].invoke if Monit.notify_queues_overloaded?
  end

  desc "Alerts (via SMS or Email) that the monit queues are overloaded"
  task :notify_queues_overloaded! => :environment do
    Monit.notify_queues_overloaded!
  end
end
