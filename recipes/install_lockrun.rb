# Installs lockrun to avoid overlapping instances of a single executable
#
# Author::  Andrew Coulton (<andrew@ingenerator.com>)
#
# Copyright 2013-17, inGenerator Ltd
cookbook_file "#{node['monitored_cron']['src_dir']}/lockrun.c" do
  action    :create
  owner     'root'
  group     'root'
  mode      0o644
end

execute 'gcc lockrun.c -o lockrun' do
  action    :run
  cwd       node['monitored_cron']['src_dir']
  user      'root'
  not_if    'which lockrun'
end

link "#{node['monitored_cron']['bin_dir']}/lockrun" do
  action :create
  to     "#{node['monitored_cron']['src_dir']}/lockrun"
end
