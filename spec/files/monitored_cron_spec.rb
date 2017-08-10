require 'spec_helper'
require_relative '../../files/default/monitored_cron.rb'

describe 'MonitoredCronRunner' do
  describe '#run' do
    let(:config_file) { '/etc/monitored_cron/our-job.json' }
    let (:config_task_name) { 'our-job' }
    let (:config_content)   { null }
    let (:subject)          { MonitoredCronRunner.run(config_file) }
    let (:syslog)           { MonitoredCronSpec::FakeSyslog.new }
    let (:task_start_time)  { Time.at(1_487_093_733.0) }
    let (:task_end_time)    { Time.at(1_487_093_733.5324) }
    let (:expect_runtime)   { '0.532' }

    before (:each) do
      allow(Syslog).to receive(:open) do |program_name|
        syslog.on_new(program_name)
        syslog
      end
      allow(Time).to receive(:now).and_return(task_start_time, task_end_time)
    end

    shared_examples 'does not output anything' do
      it 'does not output anything to stdout' do
        expect { subject }.to_not output.to_stdout_from_any_process
      end

      it 'does not output anything to stderr' do
        expect { subject }.to_not output.to_stderr_from_any_process
      end
    end

    context 'when config file does not exist' do
      let (:config_file)      { '/etc/random_stuff/no-job.json' }
      let (:config_task_name) { 'no-job' }

      before (:each) do
        allow(File).to receive(:read).with(config_file).and_raise(Errno::ENOENT)
      end

      it 'logs an alert message to syslog' do
        subject
        expect_logged('[alert] Invalid job config `/etc/random_stuff/no-job.json`: [Errno::ENOENT] No such file or directory')
      end

      include_examples 'does not output anything'
    end
    context 'when config file exists' do
      before (:each) do
        allow(File).to receive(:read).with(config_file).and_return(config_json)
      end

      context 'with invalid JSON' do
        let (:config_json) { 'this is junk' }

        it 'logs an alert message to syslog' do
          subject
          expect_logged('[alert] Invalid job config `' + config_file + '`: [JSON::ParserError] 765: unexpected token at \'this is junk\'')
        end

        include_examples 'does not output anything'
      end

      context 'when configuration is invalid' do
        {
          'No command specified' => '{"notify": {"url": "something"}}',
          'Command is not a string' => '{"command": 1}',
          'notify.url is not a string' => '{"command": "true", "notify": {"url": ["one"]}}',
          '`foobar` is not a valid notify URL' => '{"command": "true", "notify": {"url": "foobar"}}',
          '`mailto://some@one.net` is not a valid notify URL' => '{"command": "true", "notify": {"url": "mailto://some@one.net"}}',
          'locking.lockrun path required for locking' => '{"command": "true", "locking": {"retries": 2}}',
          'locking.lock_dir required for locking' => '{"command": "true", "locking": {"lockrun": "/foo"}}',
          'locking.sleep required if locking.retries used' => '{"command": "true", "locking": {"lockrun": "/lockrun", "lock_dir": "/locks", "retries": 2}}',
          'locking.retries is not an integer' => '{"command": "true", "locking": {"lockrun": "/lockrun", "lock_dir": "/locks", "retries": "Stuff", "sleep": 2}}',
          'locking.sleep is not an integer' => '{"command": "true", "locking": {"lockrun": "/lockrun", "lock_dir": "/locks", "retries": 2, "sleep": "any"}}'
        }.each do |scenario, invalid_config|

          context scenario.to_s do
            let (:config_json) { invalid_config }

            it 'logs alert message' do
              subject
              expect_logged(
                '[alert] Invalid job config `' + config_file + '`: [ArgumentError] ' + scenario
              )
            end
          end
        end
      end

      context 'with valid JSON config' do
        let (:config_command)   { 'true' }
        let (:config_notify)    { nil }
        let (:config_lock)      { nil }

        let (:config) do
          config = {
            'command' => config_command,
            'notify'  => config_notify,
            'locking' => config_lock
          }
          config.reject { |_k, v| v.nil? }
        end

        let (:config_json) { JSON.pretty_generate(config) }

        context 'when configured to obtain a process lock before execution' do
          let (:config_command) { 'echo "OK"' }
          let (:config_file)    { '/etc/monitored_cron/slow-job.json' }

          context 'with no retry configured' do
            let (:config_lock) { { 'lockrun' => '/usr/bin/lockrun', 'lock_dir' => '/var/run' } }

            it 'wraps command to execute in a lockrun process' do
              expect_any_instance_of(MonitoredCronRunner).to receive(:run_command) do |_instance, arg|
                expect(arg).to eq('/usr/bin/lockrun --lockfile=/var/run/cron-slow-job.lock -- echo "OK"')
                double(Process::Status).as_null_object
              end

              subject
            end
          end

          context 'with retry configured' do
            let (:config_lock) { { 'lockrun' => '/usr/bin/lockrun', 'lock_dir' => '/var/run', 'retries' => 2, 'sleep' => 20 } }

            it 'wraps command to execute in a lockrun process with retry args' do
              expect_any_instance_of(MonitoredCronRunner).to receive(:run_command) do |_instance, arg|
                expect(arg).to eq('/usr/bin/lockrun --lockfile=/var/run/cron-slow-job.lock --retries=2 --sleep=20 -- echo "OK"')
                double(Process::Status).as_null_object
              end

              subject
            end
          end
        end

        context 'when no locking is configured' do
          let (:config_command) { 'echo "OK"' }
          let (:config_lock)    { nil }

          it 'runs command exactly as configured with no lockrun' do
            expect_any_instance_of(MonitoredCronRunner).to receive(:run_command) do |_instance, arg|
              expect(arg).to eq('echo "OK"')
              double(Process::Status).as_null_object
            end

            subject
          end
        end

        context 'when the command is invalid' do
          let (:config_command) { '/run/some/random/process' }

          it 'logs an alert message' do
            subject
            expect_logged(
              '[alert] Failed to start: No such file or directory - /run/some/random/process'
            )
          end
        end

        context 'when the command runs successfully with no output' do
          let (:config_command) { 'true' }

          it 'logs an info message for the successful completion' do
            subject
            expect_logged("[info] Ran successfully in #{expect_runtime}s")
          end
        end

        context 'when the command fails with no output' do
          let (:config_command) { 'false' }

          it 'logs an error message for the failure' do
            subject
            expect_logged("[err] Failed with exit code 1 after #{expect_runtime}s")
          end
        end

        context 'when the command runs successfully with no error output' do
          let (:config_command) { 'echo "line 1" && echo "more"' }

          it 'logs a debug message for each line of standard output followed by info for successful completion' do
            subject
            expect_logged(
              '[debug] line 1',
              '[debug] more',
              "[info] Ran successfully in #{expect_runtime}s"
            )
          end

          include_examples 'does not output anything'
        end

        context 'when the command outputs multiple lines within a single buffer' do
          let (:config_command) { 'echo "line 1\nline 2\nline 3"' }

          it 'outputs a separate log message for each output line' do
            subject
            expect_logged(
              '[debug] line 1',
              '[debug] line 2',
              '[debug] line 3',
              "[info] Ran successfully in #{expect_runtime}s"
            )
          end
        end

        context 'when the command runs successfully but writes to stderr' do
          let (:config_command) { 'echo "first" && echo "error text" >&2 && echo "last"' }

          it 'logs interleaved stdout / stderr followed by an error message' do
            subject
            expect_logged(
              '[debug] first',
              '[warn] error text',
              '[debug] last',
              "[err] Displayed errors but exited 0 after #{expect_runtime}s"
            )
          end

          include_examples 'does not output anything'
        end

        context 'when the command exits with a nonzero status' do
          let (:config_command) { 'echo "well now" && false' }

          it 'logs interleaved stdout / stderr followed by an error message' do
            subject
            expect_logged(
              '[debug] well now',
              "[err] Failed with exit code 1 after #{expect_runtime}s"
            )
          end

          include_examples 'does not output anything'
        end

        context 'when configured with an optional notify url' do
          let (:config_notify) { { 'url' => 'http://my.web.hook/acsd23h' } }

          {
            'when the command is invalid' => '/run/some/random/process',
            'when the command fails with no output' => 'false',
            'when the command fails with output' => 'echo "broken" && false',
            'when the command runs successfully but writes to stderr' => 'echo "error text" >&2'
          }.each do |scenario, scenario_command|
            context scenario.to_s do
              let (:config_command) { scenario_command }

              it 'does not notify the URL' do
                expect(Net::HTTP).to_not receive(:get)
                subject
              end
            end
          end

          {
            'when the command runs successfully with no output' => 'true',
            'when the command runs successfully with no error output' => 'echo "stuff"'
          }.each do |scenario, scenario_command|
            context scenario.to_s do
              let (:config_command) { scenario_command }

              it 'notifies the URL' do
                expect(Net::HTTP).to receive(:get).with(URI('http://my.web.hook/acsd23h')).once
                subject
              end

              context 'when configured with a notification url template' do
                let (:config_notify)  { { 'url' => 'http://my.web.hook/ac?t=:runtime:' } }

                it 'replaces the time parameter with the task runtime in seconds and pings' do
                  expect(Net::HTTP).to receive(:get).with(URI('http://my.web.hook/ac?t=' + expect_runtime))
                  subject
                end
              end
            end
          end
        end
      end
    end

    context 'when the program is run directly' do
      let (:config_file) { Tempfile.new(['test-job', '.json']) }

      before (:each) do
        config_file.write(JSON.pretty_generate(command: 'echo "Standard stuff"',
                                               notify: { url: 'http://www.ingenerator.com/' }))
        config_file.close
      end

      after(:each) do
        config_file.unlink
      end

      it 'should run the task and produce the expected output' do
        # This spec is a rough integration test to check the script actually
        # runs. For example, it requires things that are already loaded by rspec
        # so we need to know that it works OK.
        # Because it's hard to capture syslog, we set an environment variable
        # that causes it to print messages to the screen instead
        ruby = `which ruby`.chomp
        script = File.expand_path('../../files/default/monitored_cron.rb', File.dirname(__FILE__))
        cron_name = 'cron-' + File.basename(config_file.path, '.json')

        expect_output_pattern = Regexp.new([
          '^',
          Regexp.quote("#{cron_name}: [7] Standard stuff\n"),
          Regexp.quote("#{cron_name}: [6] Ran successfully in 0.") + "[0-9]{3}s\n",
          Regexp.quote("#{cron_name}: [6] Pinged http://www.ingenerator.com/"),
          '$'
        ].join)

        cmd = "MONITORED_CRON_TEST=1 #{ruby} #{script} #{config_file.path} 2>&1"
        expect(`#{cmd}`).to match expect_output_pattern
        expect($?).to eq(0)
      end
    end
  end

  def expect_logged(*messages)
    expected = []
    messages.each do |msg|
      expected << 'cron-' + config_task_name + ': ' + msg
    end

    expect(syslog.logged_messages).to match_array(expected)
  end
end

module MonitoredCronSpec
  class FakeSyslog
    attr_reader :logged_messages

    def initialize
      @logged_messages = []
    end

    def log(level, format_string, *format_args)
      level_names = {
        Syslog::LOG_DEBUG => 'debug',
        Syslog::LOG_INFO => 'info',
        Syslog::LOG_NOTICE => 'notice',
        Syslog::LOG_WARNING => 'warn',
        Syslog::LOG_ERR => 'err',
        Syslog::LOG_ALERT  => 'alert',
        Syslog::LOG_EMERG  => 'emerg'
      }

      @logged_messages << format(
        '%s: [%s] %s',
        @program_name,
        level_names[level],
        format(format_string, *format_args)
      )
    end

    def on_new(program_name)
      @program_name = program_name
    end
  end
end
