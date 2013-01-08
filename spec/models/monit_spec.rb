require 'spec_helper'

describe Monit do

  include FakeFS::SpecHelpers

  let(:config_options) {{
    :monit => {
      :filename => "monit.yml",
      :section_ids => [
        :notify,
        :services,
        :queues
      ]
    },
    :rabbit => {:filename => "amqp.yml"},
    :overloaded_queues => {
      :filename => ".overloaded_queues.yml",
      :config => {
        "names" => {
          "queue_1" => {
            "human_name" => "human_queue_name_1",
            "limit" => "20",
            "current" => "25"
          },
          "queue_2" => {
            "human_name" => "human_queue_name_2",
            "limit" => "30",
            "current" => "34"
          }
        }
      }
    }
  }}

  def without_fakefs(&block)
    FakeFS.deactivate!
    result = yield(block)
    FakeFS.activate!
    result
  end

  def yml_file_path(name, type = :config)
    "#{Rails.root}/#{type}/#{name}"
  end

  def load_yml_file(name, type = :config)
    YAML.load_file(yml_file_path(name, type))
  end

  before do
    without_fakefs do
      config_options[:monit][:path] = yml_file_path(config_options[:monit][:filename])
      config_options[:monit][:config] = load_yml_file(config_options[:monit][:filename])
      config_options[:rabbit][:path] = yml_file_path(config_options[:rabbit][:filename])
      config_options[:rabbit][:config] = load_yml_file(config_options[:rabbit][:filename])
      config_options[:overloaded_queues][:path] = yml_file_path(config_options[:overloaded_queues][:filename], :tmp)
    end
    generate_config_file!(:monit)
  end

  def generate_config_file!(type, options = {})
    config_file = config_options[type]
    options[:config] ||= config_file[:config]
    config_path = config_file[:path]
    FileUtils.mkdir_p(File.dirname(config_path))
    File.open(config_path, 'w') do |file|
      file.write(options[:config].to_yaml)
    end
  end

  def config_section(type, *section_ids)
    config = config_options[type][:config]

    section_ids.each do |section_id|
      config ||= {}
      config = config[section_id.to_s]
    end

    config
  end

  describe ".generate_config!" do
    let(:default_output_path) { "#{Rails.root}/nuntium" }

    def monit_output(options = {})
      options[:path] ||= default_output_path
      File.open(options[:path], 'r') { |file| file.read }
    end

    def assert_monit_script(output, options = {})
      options[:services] ||= config_section(:monit, :services, :names)
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
    before do
      generate_config_file!(:rabbit)
    end

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

    let(:overloaded_queues) { ["ao_queue.1.smpp.1", "ao_queue.1.smpp.2"] }

    def queue_report(custom_queues = {})
      report = "Listing queues ...\n"
      default_queues.merge(custom_queues).each do |queue_name, num_items|
        report << "#{queue_name}\t#{num_items}\n"
      end
      report << "...done.\n"
    end

    def overloaded_queue_report(*queues_to_overload)
      options = queues_to_overload.extract_options!
      options[:queues_config] ||= config_section(:monit, :queues, :names)
      queues_for_report = {}
      queues_to_overload = overloaded_queues if queues_to_overload.empty?
      queues_to_overload.each do |queue_name|
        queues_for_report[queue_name] = options[:queues_config][queue_name]["limit"].to_i + 1
      end
      queue_report(queues_for_report)
    end

    def rabbitmq_list_queues_command(options = {})
      options[:environment] ||= Rails.env
      options[:rabbitmqctl_path] ||= "/usr/sbin/rabbitmqctl"
      "#{options[:rabbitmqctl_path]} list_queues -p '#{config_options[:rabbit][:config][options[:environment]]['vhost']}'"
    end

    def stub_list_queues(result, options = {})
      subject.class.stub(:`).with(
        rabbitmq_list_queues_command(options)
      ).and_return(result)
    end

    def assert_list_queues(options = {})
      subject.class.should_receive(:`).with(
        rabbitmq_list_queues_command(options)
      )
    end

    context "given the monitored queues are not overloaded" do
      before do
        stub_list_queues(queue_report)
      end

      it "should return an empty hash" do
        subject.class.overloaded_queues.should be_empty
      end

      context "and an overloaded queues file does not exist" do
        it "should not try to remove the non-existant file" do
          File.exists?(config_options[:overloaded_queues][:path]).should be_false
        end
      end

      context "and an overloaded queues file exists" do
        before do
          generate_config_file!(:overloaded_queues)
        end

        it "should delete the overloaded queues file" do
          subject.class.overloaded_queues
          File.exists?(config_options[:overloaded_queues][:path]).should be_false
        end
      end
    end

    context "given two of the monitored queues are overloaded" do
      before do
        stub_list_queues(overloaded_queue_report)
      end

      it "should return the monit queue configuration and the actual number of items in the queue" do
        result = subject.class.overloaded_queues
        overloaded_queues.each do |overloaded_queue|
          result[overloaded_queue]["current"].should be_present
        end
      end

      it "should write the overloaded queues to file" do
        result = subject.class.overloaded_queues
        output = load_yml_file(config_options[:overloaded_queues][:filename], :tmp)
        output["names"].should == result
        File.stat(config_options[:overloaded_queues][:path]).mode.to_s(8)[3..5].should == "646"
      end

      context "passing :write_output => false" do
        it "should not write the overloaded queues to file" do
          subject.class.overloaded_queues(:write_output => false)
          File.exists?(config_options[:overloaded_queues][:path]).should be_false
        end
      end
    end

    context "passing :environment => 'development'" do
      before do
        stub_list_queues(queue_report, :environment => "development")
      end

      it "should try to list the queues from the development vhost" do
        assert_list_queues(:environment => "development")
        subject.class.overloaded_queues(:environment => "development")
      end
    end

    context "passing :rabbitmqctl_path => '/path/to/rabbitmqctl'" do
      before do
        stub_list_queues(queue_report, :rabbitmqctl_path => "/path/to/rabbitmqctl")
      end

      it "should try to list the queues using the custom path to rabbitmqctl" do
        assert_list_queues(:rabbitmqctl_path => "/path/to/rabbitmqctl")
        subject.class.overloaded_queues(:rabbitmqctl_path => "/path/to/rabbitmqctl")
      end
    end
  end

  describe ".notify_queues_overloaded?" do
    context "given there is no overloaded queues file" do
      it "should return false" do
        subject.class.should_not be_notify_queues_overloaded
      end
    end

    context "given there is an overloaded queues file with no notified_at entry" do
      context "with no 'notified_at' entry" do
        before do
          generate_config_file!(:overloaded_queues)
        end

        it "should return true" do
          subject.class.should be_notify_queues_overloaded
        end
      end

      context "with a 'notified_at' entry" do
        let(:overloaded_queues_config) { config_options[:overloaded_queues][:config] }

        def set_notified_at(mins_ago)
          config_options[:overloaded_queues][:config]["notified_at"] = Time.now - mins_ago * 60
        end

        context "that was more than 30 mins ago" do
          before do
            set_notified_at(30)
            generate_config_file!(:overloaded_queues, :config => overloaded_queues_config)
          end

          it "should return true" do
            subject.class.should be_notify_queues_overloaded
          end
        end

        context "that was less than 20 mins ago" do
          before do
            set_notified_at(20)
            generate_config_file!(:overloaded_queues, :config => overloaded_queues_config)
          end

          it "should return false" do
            subject.class.should_not be_notify_queues_overloaded
          end

          context "passing :notify_every => 10" do
            it "should return true" do
              subject.class.should be_notify_queues_overloaded(:notify_every => 10)
            end
          end
        end
      end
    end
  end

  describe ".notify_queues_overloaded!" do

    def notify_config(section_id, *fields)
      config_section(:monit, section_id, :notify, *fields) || config_section(:monit, :notify, *fields)
    end

    context "the queues are overloaded" do
      let(:application_id) { notify_config(:application_id) }

      let(:application) do
        without_fakefs do
          create(:application, :id => application_id)
        end
      end

      before do
        generate_config_file!(:overloaded_queues)
        Application.stub(:find).and_return(application)
      end

      it "should try to send an sms to the relevant notify person" do
        application.should_receive(:route_ao).once.with do |sms, interface|
          sms.from.should be_nil
          sms.to.should == "sms://#{notify_config(:queues, :channels, :sms, :to).first}"
          sms.body.should =~ /Nuntium Queue\(s\) Overloaded\! \w+ \(\d+\), \w+ \(\d+\)/
          interface.should == "http"
        end
        subject.class.notify_queues_overloaded!
      end

      it "should write an 'updated_at' field to the queues file" do
        File.should_not_receive(:chmod)
        subject.class.notify_queues_overloaded!
        output = load_yml_file(config_options[:overloaded_queues][:filename], :tmp)
        output["notified_at"].should be_present
      end
    end

    context "the queues are not overloaded" do
      it "should not notify" do
        subject.class.notify_queues_overloaded!.should be_false
      end
    end
  end
end
