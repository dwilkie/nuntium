namespace :monit do
  desc "Creates the monit configuration for your environment"
  task :generate => :environment do
    path = Monit.generate_config!
    puts "wrote monit config for #{Rails.env} environment to #{path}"
  end
end
