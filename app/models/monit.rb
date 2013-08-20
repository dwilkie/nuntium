require 'yaml'
require 'fileutils'

class Monit

  FILES = {
    :config => {
      :monit => "monit.yml",
      :rabbit => "amqp.yml"
    },
    :tmp => {
      :overloaded_queues => ".overloaded_queues.yml"
    }
  }.freeze

  def self.generate_config!(options = {})
    services = monit_config(:services, :names)
    monit_script = build_config(services).join("\n\n")
    options[:path] ||= "#{rails_root}/nuntium"
    write_file(options[:path], monit_script)
    options[:path]
  end

  def self.overloaded_queues(options = {})
    set_rails_env(options[:environment])
    options[:rabbitmqctl_path] ||= "/usr/sbin/rabbitmqctl"
    options[:write_output] = true unless options[:write_output] == false

    queues_config = monit_config(:queues, :names)
    queue_status = `#{options[:rabbitmqctl_path]} list_queues -p '#{rabbit_config['vhost']}'`
    monitored_overloaded_queue_names = {}

    queue_status.split(/\n/).each do |queue|
      queue_data = queue.split(/\t/)
      queue_name = queue_data[0]
      items_in_queue = queue_data[1].to_i
      queue_config = queues_config[queue_name]
      if queue_config && queue_config["limit"] && items_in_queue > queue_config["limit"]
        overloaded_queue_config = queue_config.merge("current" => items_in_queue)
        previous_items_in_queue = previous_items_in_queue(queue_name)
        overloaded_queue_config.merge!("previous" => previous_items_in_queue) if previous_items_in_queue
        monitored_overloaded_queue_names[queue_name] = overloaded_queue_config
      end
    end

    if options[:write_output]
      if monitored_overloaded_queue_names.any?
        update_overloaded_queues_file({"names" => monitored_overloaded_queue_names}, :chmod => true)
      else
        clear_overloaded_queues_file
      end
    end

    monitored_overloaded_queue_names
  end

  def self.notify_queues_overloaded?(options = {})
    options[:notify_every] ||= (30 * 60)
    last_notified_at = overloaded_queues_file["notified_at"]
    overloaded_queues_file.any? && (last_notified_at.nil? || last_notified_at < Time.now - options[:notify_every])
  end

  def self.notify_queues_overloaded!(options = {})
    set_rails_env(options[:environment])
    overloaded_queues = overloaded_queues_file
    overloaded_queue_names = overloaded_queues["names"] || {}
    if overloaded_queue_names.any?
      overloaded_queue_names.each do |overloaded_queue, metadata|
        if overloaded_channel = metadata["channel"]
          Channel.find_by_name!(overloaded_channel).switch_to_backup
        end
      end
      queue_summary = overloaded_queue_names.values.map {|queue| "#{queue['human_name']} (#{queue['current']})" }.join(", ")
      notify_channels!(:queues, "Nuntium Queue(s) Overloaded! #{queue_summary}")
      update_overloaded_queues_file({"notified_at" => Time.now})
    end
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

  def self.previous_items_in_queue(queue_name)
    overloaded_queue_names = overloaded_queues_file["names"] || {}
    overloaded_queue = overloaded_queue_names[queue_name] || {}
    overloaded_queue["current"]
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

  def self.notify_via_sms!(section_id, message)
    application_id = notify_config(section_id, :application_id)
    recipients = notify_config(section_id, :channels, :sms, :to)
    return unless (application_id && recipients)
    application = Application.find(application_id)
    recipients.each do |recipient, channel|
      sms = application.ao_messages.build(
        :to => "sms://#{recipient}", :body => message, :suggested_channel => channel
      )
      application.route_ao sms, "http"
    end
  end

  def self.notify_via_email!(section_id, message)
    application_id = notify_config(section_id, :application_id)
    notify_email = notify_config(section_id, :channels, :email)
    return unless (application_id && notify_email)
    account = Application.find(application_id).account
    AlertMailer.error(account, message, nil).deliver if account.alert_emails.present?
  end

  def self.notify_channels!(section_id, message)
    notify_via_sms!(section_id, message)
    notify_via_email!(section_id, message)
  end

  def self.notify_config(section_id, *fields)
    load_config_section(monit_config(section_id.to_s)["notify"], *fields) || load_config_section(monit_config["notify"], *fields)
  end

  def self.monit_config(*section_ids)
    @monit_config ||= load_yml_file(:monit)
    load_config_section(@monit_config, *section_ids)
  end

  def self.overloaded_queues_file
    @overloaded_queues = load_yml_file(:overloaded_queues, :tmp) || {}
  end

  def self.update_overloaded_queues_file(new_content, options = {})
    options[:old_content] ||= overloaded_queues_file
    write_file(
      yml_file(:overloaded_queues, :tmp), options[:old_content].merge(new_content).to_yaml, options[:chmod]
    )
  end

  def self.clear_overloaded_queues_file
    path = yml_file(:overloaded_queues, :tmp)
    FileUtils.rm(path) if File.exists?(path)
  end

  def self.rabbit_config
    @rabbit_config ||= load_yml_file(:rabbit)
    load_config_section(@rabbit_config, rails_env)
  end

  def self.load_config_section(config, *section_ids)
    section_ids.each do |section_id|
      config ||= {}
      config = config[section_id.to_s]
    end

    config
  end

  def self.load_yml_file(name, type = :config)
    path = yml_file(name, type)
    YAML.load_file(path) if File.exists?(path)
  end

  def self.yml_file(name, type = :config)
    File.expand_path("#{rails_root}/#{type}/#{FILES[type][name]}", __FILE__)
  end

  def self.rails_root
    File.expand_path("../../../", __FILE__)
  end

  def self.rails_env
    @rails_env ||= (defined?(Rails) ? Rails.env : (ENV["RAILS_ENV"] || "production"))
  end

  def self.set_rails_env(environment)
    @rails_env = environment
  end

  def self.write_file(path, data, all_writable = false)
    FileUtils.mkdir_p(File.dirname(path))
    if all_writable
      FileUtils.touch(path) unless File.exists?(path)
      File.chmod(0646, path)
    end
    File.open(path, 'w') { |file| file.write(data) }
  end
end
