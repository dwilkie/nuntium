require File.expand_path("../../../app/models/monit", __FILE__)

namespace :monit do
  desc "Creates the monit configuration for your environment"
  task :generate do
    path = Monit.generate_config!
    puts "wrote monit config for #{Rails.env} environment to #{path}"
  end
end
