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

directory node['monitored_cron']['lock_dir'] do
  owner 'root'
  group 'root'
  mode 0o722
  recursive true
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
