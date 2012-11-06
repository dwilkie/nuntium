require 'spec_helper'

def config_file_path(name)
  "#{Rails.root}/config/#{name}"
end

def load_config_file(name)
  YAML.load_file(config_file_path(name))
end

describe Monit do

  CONFIG_OPTIONS = {
    :monit => {
      :filename => "monit_services.yml",
      :section_ids => {
        :nuntium_services => "nuntium_services",
        :queues => "queues"
      }
    },
    :rabbit => {:filename => "amqp.yml"}
  }

  CONFIG_OPTIONS[:monit][:path] = config_file_path(CONFIG_OPTIONS[:monit][:filename])
  CONFIG_OPTIONS[:monit][:config] = load_config_file(CONFIG_OPTIONS[:monit][:filename])

  CONFIG_OPTIONS[:rabbit][:path] = config_file_path(CONFIG_OPTIONS[:rabbit][:filename])
  CONFIG_OPTIONS[:rabbit][:config] = load_config_file(CONFIG_OPTIONS[:rabbit][:filename])

  CONFIG_OPTIONS.freeze

  def generate_config_file!(type, options = {})
    config_options = CONFIG_OPTIONS[type]
    options[:config] ||= config_options[:config]
    config_path = config_options[:path]
    FileUtils.mkdir_p(File.dirname(config_path))
    File.open(config_path, 'w') do |file|
      file.write(options[:config].to_yaml)
    end
  end

  def config_section(type, section_id)
    CONFIG_OPTIONS[type][:config][CONFIG_OPTIONS[type][:section_ids][section_id]]
  end

  include FakeFS::SpecHelpers

  describe ".generate_config!" do
    let(:default_output_path) { "#{Rails.root}/nuntium" }

    def monit_output(options = {})
      options[:path] ||= default_output_path
      File.open(options[:path], 'r') { |file| file.read }
    end

    def assert_monit_script(output, options = {})
      options[:services] ||= config_section(:monit, :nuntium_services)
      options[:services].each do |service|
        if service.is_a?(Hash)
          service_name = service.keys.first
          service.values.first.each do |type, worker_id|
            assert_pidfile(output, service_name, type, worker_id)
            assert_operate_service(output, service_name, "start", type, worker_id)
            assert_operate_service(output, service_name, "stop", type, worker_id)
          end
        else
          service_name = service
          assert_pidfile(output, service_name)
          assert_operate_service(output, service_name, "start")
          assert_operate_service(output, service_name, "stop")
        end

        output.should include("check process nuntium_#{service_name}")
        output.should include("group nuntium")
      end
    end

    def assert_operate_service(output, service_name, action, type = nil, worker_id = nil)
      operation_string = %{#{action} "/bin/su - #{ENV['USER']} -c '#{Rails.root}/script/nuntium_service.sh #{service_name}_daemon_ctl.rb #{action} #{Rails.env}}
      operation_string << " #{type}" if type
      operation_string << " #{worker_id}" if worker_id
      operation_string << %{'"}
      output.should include(operation_string)
    end

    def assert_pidfile(output, service_name, type = nil, worker_id = nil)
      pidfile_string = "with pidfile #{Rails.root}/tmp/pids/#{service_name}_daemon"
      pidfile_string << ".#{type}" if type
      pidfile_string << ".#{worker_id}." if worker_id
      pidfile_string << ".pid"
      output.should include(pidfile_string)
    end

    context "given there's a nuntium monit services config file 'config/monit_services.yml'" do
      before do
        generate_config_file!(:monit)
      end

      context "passing no options" do
        it "create a monit script under the Rails root directory" do
          subject.class.generate_config!.should == default_output_path
          assert_monit_script(monit_output)
        end
      end

      context "passing :path => '/home/monit_script'" do
        it "should create a monit script under '/home/monit_script'" do
          subject.class.generate_config!(:path => "/home/monit_script").should == "/home/monit_script"
          assert_monit_script(monit_output(:path => "/home/monit_script"))
        end
      end
    end
  end

  describe ".overloaded_queues" do

    let(:default_queues) {{
      "ao_queue.1.twilio.6" => 68,
      "ao_queue.1.smpp.4" => 0,
      "application_queue.1" => 0,
      "ao_queue.1.smpp.5" => 0,
      "ao_queue.1.smpp.9" => 0,
      "notifications_queue_managed_processes_managed_processes" => 0,
      "notifications_queue_slow_1" => 0,
      "cron_tasks_queue" => 0,
      "ao_queue.1.smpp.1" => 0,
      "notifications_queue_fast_1" => 0,
      "ao_queue.1.smpp.2" => 0
    }}

    def queue_report(custom_queues = {})
      report = "Listing queues ...\n"
      default_queues.merge(custom_queues).each do |queue_name, num_items|
        report << "#{queue_name}\t#{num_items}\n"
      end
      report << "...done.\n"
    end

    def overloaded_queue_report(*queues_to_overload)
      options = queues_to_overload.extract_options!
      options[:queues_config] ||= config_section(:monit, :queues)
      queues_for_report = {}
      queues_to_overload.each do |queue_name|
        queues_for_report[queue_name] = options[:queues_config][queue_name]["limit"].to_i + 1
      end
      queue_report(queues_for_report)
    end

    def rabbitmq_list_queues_command(environment = nil)
      environment ||= Rails.env
      "rabbitmqctl list_queues -p '#{CONFIG_OPTIONS[:rabbit][:config][environment]['vhost']}'"
    end

    def stub_list_queues(result, environment = nil)
      subject.class.stub(:`).with(
        rabbitmq_list_queues_command(environment)
      ).and_return(result)
    end

    def assert_list_queues(environment = nil)
      subject.class.should_receive(:`).with(
        rabbitmq_list_queues_command(environment)
      )
    end

    before do
      generate_config_file!(:rabbit)
      generate_config_file!(:monit)
    end

    context "given the monitored queues are not overloaded" do
      before do
        stub_list_queues(queue_report)
      end

      it "should return an empty hash" do
        subject.class.overloaded_queues.should be_empty
      end
    end

    context "given two of the monitored queues are overloaded" do
      before do
        stub_list_queues(overloaded_queue_report("ao_queue.1.smpp.1", "ao_queue.1.smpp.2"))
      end

      it "should return the monit queue configuration and the actual number of items in the queue" do
        result = subject.class.overloaded_queues
        result["ao_queue.1.smpp.1"]["current"].should be_present
        result["ao_queue.1.smpp.2"]["current"].should be_present
      end
    end

    context "passing 'development'" do
      before do
        stub_list_queues(queue_report, "development")
      end

      it "should try to list the queues from the development vhost" do
        assert_list_queues("development")
        subject.class.overloaded_queues("development")
      end
    end
  end
end
