require File.expand_path("../../../app/models/monit", __FILE__)

namespace :monit do
  desc "Creates the monit configuration for your environment"
  task :generate do
    path = Monit.generate_config!
    puts "wrote monit config for #{Rails.env} environment to #{path}"
  end

  desc "Monitors the nuntium queues to see if they're overloaded"
  task :queues do
    fail("Queues are overloaded!") if Monit.overloaded_queues.any?
  end
end
