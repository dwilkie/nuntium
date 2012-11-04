require 'spec_helper'

describe Monit do
  NUNTIUM_MONIT_CONFIG = YAML.load_file(File.join(Rails.root, 'config', 'monit_services.yml')).freeze

  describe ".generate_config!" do
    include FakeFS::SpecHelpers

    NUNTIUM_SERVICES_SECTION_ID = "nuntium_services".freeze
    DEFAULT_NUNTIUM_SERVICES = NUNTIUM_MONIT_CONFIG[NUNTIUM_SERVICES_SECTION_ID].freeze
    CONFIG_FILE_PATH = "#{Rails.root}/config/monit_services.yml".freeze

    let(:default_output_path) { "#{Rails.root}/nuntium" }

    def monit_output(options = {})
      options[:path] ||= default_output_path
      File.open(options[:path], 'r') { |file| file.read }
    end

    def generate_nuntium_monit_config_file!(options = {})
      options[:services] ||= DEFAULT_NUNTIUM_SERVICES
      FileUtils.mkdir_p(File.dirname(CONFIG_FILE_PATH))
      File.open(CONFIG_FILE_PATH, 'w') do |file|
        file.write({NUNTIUM_SERVICES_SECTION_ID => options[:services]}.to_yaml)
      end
    end

    def assert_monit_script(output, options = {})
      options[:services] ||= DEFAULT_NUNTIUM_SERVICES
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
        generate_nuntium_monit_config_file!
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
end
