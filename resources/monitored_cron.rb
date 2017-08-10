# monitored_cron schedules a command to be run as a cron, with output and errors
# sent to syslog and - optionally - an HTTP ping notification to a monitoring
# endpoint.
#
# See the README for full usage information
#
resource_name :monitored_cron

# User-friendly task name, must be filesystem-safe
property :name, String, name_property: true, regex: /^[a-zA-Z0-9\-\_]+$/

# Actual command to run
property :command, String, required: true

# Either {time: :daily} or a cron expression as {minute => 2, hour:12} etc
property :schedule, Hash, required: true, callbacks: {
  'schedule must not be empty' => lambda do |val|
    val.length >= 1
  end,
  'schedule cannot combine time: with any other value' => lambda do |val|
    (val.length == 1) || ! (val.key?(:time) || val.key?('time'))
  end
}

# User to run as
property :user, String, default: 'root'

# Whether to lock so only one instance can run at a time
property :require_lock, [TrueClass, FalseClass], default: false

# If locking, how many times to retry getting a lock
property :lock_retries, Integer

# If locking, how long to wait between retries
property :lock_sleep, Integer

# Optionally ping this URL when the task succeeds. You can include :runtime: in
# any part of the URL and it will be replaced with the number of seconds the task
# ran.
property :notify_url, String, regex: URI.regexp(%w(http https))

default_action :create

action :create do
  require_included_recipe('monitored-cron::install', 'Required to use monitored_cron')
  require_included_recipe('monitored-cron::install_lockrun', 'Required for locking') if new_resource.require_lock

  file job_file_path do
    content ::JSON.pretty_generate(job_config)
    owner   new_resource.user
    group   'root'
    mode    0o600
  end

  schedule_symbols = schedule_as_symbols

  cron cron_name do
    command cron_command
    user    new_resource.user
    if schedule_symbols[:time]
      time schedule_symbols[:time]
    else
      minute schedule_symbols[:minute] if schedule_symbols[:minute]
      hour schedule_symbols[:hour] if schedule_symbols[:hour]
      day schedule_symbols[:day] if schedule_symbols[:day]
      month schedule_symbols[:month] if schedule_symbols[:month]
      weekday schedule_symbols[:weekday] if schedule_symbols[:weekday]
    end
  end
end

action :delete do
  file job_file_path do
    action :delete
  end

  cron cron_name do
    action :delete
  end
end

action_class do

  def cron_name
    'monitored-' + new_resource.name
  end

  # Path to the JSON job file for this job
  def job_file_path
    ::File.join(node['monitored_cron']['job_dir'], new_resource.name + '.json')
  end

  # Builds the config JSON
  def job_config
    config = { command: new_resource.command }
    config['notify'] = notify_config if new_resource.notify_url
    config['locking'] = locking_config if new_resource.require_lock
    config
  end

  # Builds the notify section of config json
  def notify_config
    { url: new_resource.notify_url }
  end

  # Depending on the user's resource syntax / whether the schedule has come from
  # attributes, it may be keyed with either symbols or strings. fix that.
  def schedule_as_symbols
    new_resource.schedule.inject({}){ |memo,(k,v)| memo[k.to_sym] = v; memo }
  end

  # Builds the locking section of config json
  def locking_config
    cfg = {
      lockrun: ::File.join(node['monitored_cron']['bin_dir'], 'lockrun'),
      lock_dir: node['monitored_cron']['lock_dir']
    }
    cfg['retries'] = new_resource.lock_retries if new_resource.lock_retries
    cfg['sleep'] = new_resource.lock_sleep if new_resource.lock_sleep
    cfg
  end

  def require_included_recipe(recipe, message)
    raise "Missing recipe #{recipe}: #{message}" unless node.recipe?(recipe)
  end

  # Format the actal shell command that cron will be asked to run
  def cron_command
    [
      '/usr/bin/ruby',
      ::File.join(node['monitored_cron']['src_dir'], 'monitored_cron.rb'),
      job_file_path
    ].join(' ')
  end
end
