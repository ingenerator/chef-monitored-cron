# Location where the wrapper script and other source files will go
default['monitored_cron']['src_dir'] = '/usr/local/src/monitored_cron'
# Location for the lockrun binary
default['monitored_cron']['bin_dir'] = '/usr/local/bin'
# Job files will be provisioned here
default['monitored_cron']['job_dir'] = '/etc/monitored_cron/jobs'
# Lock files will go here
default['monitored_cron']['lock_dir'] = '/var/run/monitored_cron'
