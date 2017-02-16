monitored_cron node['test']['name'] do
  command      node['test']['command']
  schedule     node['test']['schedule']
  user         node['test']['user'] if node['test']['user']
  notify_url   node['test']['notify_url'] if node['test']['notify_url']
  require_lock node['test']['require_lock'] if node['test']['require_lock']
  lock_retries node['test']['lock_retries'] if node['test']['lock_retries']
  lock_sleep   node['test']['lock_sleep'] if node['test']['lock_sleep']
end
