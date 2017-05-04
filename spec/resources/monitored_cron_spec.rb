require 'spec_helper'

describe_resource 'resources::monitored_cron' do
  let (:converge_what) do
    %w(monitored-cron::install test_helpers::test_monitored_cron)
  end

  let (:resource) { 'monitored_cron' }

  let (:node_attributes) do
    {
      test: { name: 'my-cron', command: '/path/to/task', schedule: { time: :daily } }
    }
  end

  describe 'create' do
    it 'raises a validation exception if schedule is empty' do
      chef_runner.node.normal['test']['schedule'] = {}
      expect { chef_run }.to raise_error(Chef::Exceptions::ValidationFailed, /not be empty/)
    end

    it 'raises a validation exception if schedule has time interval and crontab fields' do
      chef_runner.node.normal['test']['schedule'] = { time: :daily, day: 5 }
      expect { chef_run }.to raise_error(
        Chef::Exceptions::ValidationFailed,
        /cannot combine time: with any other value/
      )
    end

    it 'raises a validation exception if name is not alphanumeric' do
      chef_runner.node.normal['test']['name'] = 'well this is junk'
      expect { chef_run }.to raise_error(
        Chef::Exceptions::ValidationFailed,
        /does not match regular expression/
      )
    end

    context 'when monitored_cron is not installed' do
      let (:converge_what) { ["test_helpers::test_#{resource}"] }

      it 'raises an exception' do
        expect { chef_run }.to raise_error(RuntimeError, /monitored-cron::install/)
      end
    end

    context 'when monitored_cron is installed without lockrun' do
      let (:converge_what) { %w(monitored-cron::install test_helpers::test_monitored_cron) }
      let (:node_attributes) do
        {
          monitored_cron: {
            src_dir: '/src/monitored_cron',
            job_dir: '/etc/jobs'
          },
          test: {
            name: 'some-task',
            command: '/path/to/exe --with=arg',
            user: 'cron-user',
            require_lock: false,
            schedule: { time: :daily }
          }
        }
      end

      it 'provisions a job JSON file with expected config' do
        expect(chef_run).to create_file('/etc/jobs/some-task.json').with(
          content: JSON.pretty_generate(command: '/path/to/exe --with=arg'),
          group:   'root',
          owner:   'cron-user',
          mode:    0o600
        )
      end

      it 'optionally configures a notify URL for the job' do
        chef_runner.node.normal['test']['notify_url'] = 'http://foo.bar/abd'
        expect(chef_run).to create_file('/etc/jobs/some-task.json').with(
          content: JSON.pretty_generate(
            command: '/path/to/exe --with=arg', notify: { url: 'http://foo.bar/abd' }
          )
        )
      end

      it 'creates a crontab entry for the job' do
        expect(chef_run).to create_cron('monitored-some-task').with(
          command: '/usr/bin/ruby /src/monitored_cron/monitored_cron.rb /etc/jobs/some-task.json',
          user:    'cron-user'
        )
      end

      it 'specifies the correct cron schedule when using a time interval' do
        chef_runner.node.normal['test']['schedule'] = { time: :daily }
        expect(chef_run).to create_cron('monitored-some-task').with(
          command: '/usr/bin/ruby /src/monitored_cron/monitored_cron.rb /etc/jobs/some-task.json',
          time:    :daily
        )
      end

      it 'specifies the correct cron schedule when using time components' do
        chef_runner.node.normal['test']['schedule'] = { day: 5, hour: 10 }
        expect(chef_run).to create_cron('monitored-some-task').with(
          command: '/usr/bin/ruby /src/monitored_cron/monitored_cron.rb /etc/jobs/some-task.json',
          time:    nil,
          day:     '5',
          hour:    '10',
          minute:  '*'
        )
      end

      it 'specifies the correct cron schedule even if the user specifies time as symbols' do
        chef_runner.node.normal['test']['schedule_symbols'] = {:minute => 5}
        expect(chef_run).to create_cron('monitored-some-task').with(
          command: '/usr/bin/ruby /src/monitored_cron/monitored_cron.rb /etc/jobs/some-task.json',
          time:    nil,
          hour:    '*',
          minute:  '5'
        )
      end

      context 'when job is configured with locking' do
        let (:node_attributes) do
          {
            monitored_cron: { job_dir: '/etc/jobs' },
            test: {
              name: 'some-task',
              command: '/path/to/exe --with=arg',
              user: 'cron-user',
              require_lock: true,
              schedule: { time: :daily }
            }
          }
        end

        it 'raises an exception' do
          expect { chef_run }.to raise_error(RuntimeError, /monitored-cron::install_lockrun/)
        end
      end
    end

    context 'when monitored_cron is installed with lockrun' do
      let (:converge_what) { %w(monitored-cron::install monitored-cron::install_lockrun test_helpers::test_monitored_cron) }
      before(:each) do
        stub_command('which lockrun').and_return('/bin/lockrun')
      end

      context 'when job is configured with locking' do
        let (:node_attributes) do
          {
            monitored_cron: {
              job_dir: '/etc/jobs',
              bin_dir: '/run',
              lock_dir: '/run/lock'
            },
            test: {
              name: 'slow-task',
              command: '/path/to/exe --with=arg',
              require_lock: true,
              schedule: { time: :annually }
            }
          }
        end

        it 'includes the lockrun details in the JSON' do
          expect(chef_run).to create_file('/etc/jobs/slow-task.json').with(
            content: JSON.pretty_generate(
              command: '/path/to/exe --with=arg',
              locking: {
                lockrun: '/run/lockrun',
                lock_dir: '/run/lock'
              }
            )
          )
        end

        it 'optionally includes retry options in the JSON' do
          chef_runner.node.normal['test']['lock_retries'] = 2
          chef_runner.node.normal['test']['lock_sleep'] = 20
          expect(chef_run).to create_file('/etc/jobs/slow-task.json').with(
            content: JSON.pretty_generate(
              command: '/path/to/exe --with=arg',
              locking: {
                lockrun: '/run/lockrun',
                lock_dir: '/run/lock',
                retries: 2,
                sleep: 20
              }
            )
          )
        end
      end
    end
  end

  describe 'delete' do
    let (:node_attributes) do
      {
        monitored_cron: {
          job_dir: '/etc/jobs'
        },
        test: {
          action: 'delete',
          name:   'my-task',
          command: '/path/to/exe --with=arg',
          schedule: { time: :annually }
        }
      }
    end

    it 'deletes the job JSON file' do
      expect(chef_run).to delete_file('/etc/jobs/my-task.json')
    end

    it 'deletes the crontab entry for the job' do
      expect(chef_run).to delete_cron('monitored-my-task')
    end

  end
end
