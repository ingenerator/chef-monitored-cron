# Installs the monitored-cron wrapper script and provisions required directories
#
# Author::  Andrew Coulton (<andrew@ingenerator.com>)
# Copyright 2017, inGenerator Ltd

directory node['monitored_cron']['src_dir'] do
  action    :create
  owner     'root'
  group     'root'
  mode      0o755
  recursive true
end

lock_dir = node['monitored_cron']['lock_dir']

directory lock_dir do
  owner 'root'
  group 'root'
  mode 0o733
  recursive true
end

# In many cases the lock directory will be on tmpfs and wiped on a reboot
# There's no guarantee a cron user has permission to recreate it, so schedule
# root to always recreate it on reboot. This doesn't need to be monitored_cron
cron 'ensure-cron-lock-dir' do
  command format('[ -d %s ] || mkdir -p -m0733 %s', lock_dir, lock_dir)
  time    :reboot
end

directory node['monitored_cron']['job_dir'] do
  owner 'root'
  group 'root'
  mode 0o755
  recursive true
end

cookbook_file File.join(node['monitored_cron']['src_dir'], 'monitored_cron.rb') do
  owner 'root'
  group 'root'
  mode 0o755
end
