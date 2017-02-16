directory node['monitored_cron']['lock_dir'] do
  owner 'root'
  group 'root'
  mode 0o722
end

directory node['monitored_cron']['job_dir'] do
  owner 'root'
  group 'root'
  mode 0o755
end

cookbook_file File.join(node['monitored_cron']['src_dir'], 'monitored_cron.rb') do
  owner 'root'
  group 'root'
  mode 0o755
end
