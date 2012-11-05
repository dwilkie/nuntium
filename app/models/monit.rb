require 'yaml'

class Monit
  def self.generate_config!(options = {})
    services = monit_config("nuntium_services")
    monit_script = build_config(services).join("\n\n")
    options[:path] ||= "#{rails_root}/nuntium"
    File.open(options[:path], 'w') { |file| file.write(monit_script) }
    options[:path]
  end

  def self.overloaded_queues(environment = nil)
    @rails_env = environment
    queues_config = monit_config("queues")
    queue_status = `rabbitmqctl list_queues -p #{rabbit_config['vhost']}`
    monitored_overloaded_queues = {}

    queue_status.split(/\n/).each do |queue|
      queue_data = queue.split(/\t/)
      queue_name = queue_data[0]
      items_in_queue = queue_data[1].to_i
      queue_config = queues_config[queue_name]
      if queue_config && queue_config["limit"] && items_in_queue > queue_config["limit"]
        monitored_overloaded_queues[queue_name] = queue_config.merge("current" => items_in_queue)
      end
    end

    monitored_overloaded_queues
  end

  private

  def self.build_config(services)
    configs = []

    services.each do |service, script_config|
      if service.is_a?(Hash)
        configs << working_group_configs(service)
      else
        configs << service_config(service, script_config)
      end
    end
    configs.flatten
  end

  def self.working_group_configs(service)
    configs = []
    service_name = service.keys.first
    service_names = {}
    service[service_name].each do |working_group, num_instances|
      num_instances.times do |instance_id|
        service_names["#{service_name}_#{working_group}_#{instance_id + 1}"] = {
          :script_name => service_name,
          :working_group => working_group,
          :instance_id => instance_id + 1
        }
      end
    end

    configs << build_config(service_names)
  end

  def self.service_config(service, script_config)
    script_options = []
    if script_config
      script_name = script_config[:script_name]
      script_options << script_config[:working_group]
      script_options << script_config[:instance_id]
    else
      script_name = service
    end

    root_dir = rails_root
    current_user = ENV['USER']

    script_args = "#{rails_env} #{script_options.join(' ')}".strip

    full_script_name = "#{script_name}_daemon"
    pid_name = full_script_name
    pid_name += ".#{script_options.join('.')}." unless script_options.empty?

    "check process nuntium_#{service}
      with pidfile #{root_dir}/tmp/pids/#{pid_name}.pid
      start \"/bin/su - #{current_user} -c '#{root_dir}/script/nuntium_service.sh #{full_script_name}_ctl.rb start #{script_args}'\"
      stop \"/bin/su - #{current_user} -c '#{root_dir}/script/nuntium_service.sh #{full_script_name}_ctl.rb stop #{script_args}'\"
      group nuntium"
  end

  def self.monit_config(*section_ids)
    load_config("monit_services.yml", *section_ids)
  end

  def self.rabbit_config
    load_config("amqp.yml", rails_env)
  end

  def self.load_config(name, *section_ids)
    config = YAML.load_file(config_file(name))

    section_ids.each do |section_id|
      config = config[section_id]
    end

    config
  end

  def self.config_file(name)
    File.expand_path("#{rails_root}/config/#{name}", __FILE__)
  end

  def self.rails_root
    File.expand_path("../../../", __FILE__)
  end

  def self.rails_env
    @rails_env ||= (defined?(Rails) ? Rails.env : (ENV["RAILS_ENV"] || "development"))
  end
end
