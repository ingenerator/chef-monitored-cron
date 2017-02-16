# notification_trigger is a no-op resource that just provides a place to manually
# queue delayed notifications, for example for a service that should always be
# reloaded after a provisioning run.
#
# Use it like:
#
#   notification_trigger 'Flush opcode cache' do
#     notifies :reload, 'service[apache2]', :delayed
#   end
#
resource_name :monitored_cron

property :name, String, name_property: true
property :command, String, required: true
property :schedule, Hash, required: true, callbacks: {
  'schedule must not be empty' => lambda do |val|
    val.length >= 1
  end,
  'schedule cannot combine time: with any other value' => lambda do |val|
    (val.length == 1) || (!val.key? :time)
  end
}
property :user, String, default: 'root'
property :require_lock, [TrueClass, FalseClass], default: false
property :lock_retries, Integer
property :lock_sleep, Integer
property :require_lock, [TrueClass, FalseClass], default: false
property :notify_url, String, regex: URI.regexp(%w(http https))

default_action :create

action :create do
  require_recipe('monitored-cron::install', 'Required to use monitored_cron')
  require_recipe('monitored-cron::install_lockrun', 'Required for locking') if require_lock

  file job_file_path do
    content ::JSON.pretty_generate(job_config)
    owner   new_resource.user
    group   'root'
    mode    0o600
  end

  cron 'monitored-some-task' do
    command cron_command
    user    new_resource.user
    if new_resource.schedule['time']
      time new_resource.schedule['time']
    else
      minute new_resource.schedule['minute'] if new_resource.schedule['minute']
      hour new_resource.schedule['hour'] if new_resource.schedule['hour']
      day new_resource.schedule['day'] if new_resource.schedule['day']
      month new_resource.schedule['month'] if new_resource.schedule['month']
      weekday new_resource.schedule['weekday'] if new_resource.schedule['weekday']
    end
  end
end

action_class do
  def job_file_path
    ::File.join(node['monitored_cron']['job_dir'], name + '.json')
  end

  def job_config
    config = { command: new_resource.command }
    config['notify'] = notify_config if new_resource.notify_url
    config['locking'] = locking_config if new_resource.require_lock
    config
  end

  def notify_config
    { url: new_resource.notify_url }
  end

  def locking_config
    cfg = {
      lockrun: ::File.join(node['monitored_cron']['bin_dir'], 'lockrun'),
      lock_dir: node['monitored_cron']['lock_dir']
    }
    cfg['retries'] = new_resource.lock_retries if new_resource.lock_retries
    cfg['sleep'] = new_resource.lock_sleep if new_resource.lock_sleep
    cfg
  end

  def require_recipe(recipe, message)
    raise "Missing recipe #{recipe}: #{message}" unless node.recipe?(recipe)
  end

  def cron_command
    [
      '/usr/bin/ruby',
      ::File.join(node['monitored_cron']['src_dir'], 'monitored_cron.rb'),
      job_file_path
    ].join(' ')
  end
end
