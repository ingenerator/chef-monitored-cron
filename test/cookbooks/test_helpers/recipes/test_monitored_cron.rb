# Have to do this nasty workaround because the attributes from chefspec are
# always string keys, but it's possible for them to be symbols if used direct
# in a recipe
if node['test']['schedule_symbols']
  schedule = {}
  node['test']['schedule_symbols'].each do | k, v |
    schedule[k.to_sym] = v
  end
else
  schedule = node['test']['schedule']
end

monitored_cron node['test']['name'] do
  action       node['test']['action'].to_sym if node['test']['action']
  command      node['test']['command']
  schedule     schedule
  user         node['test']['user'] if node['test']['user']
  notify_url   node['test']['notify_url'] if node['test']['notify_url']
  require_lock node['test']['require_lock'] if node['test']['require_lock']
  lock_retries node['test']['lock_retries'] if node['test']['lock_retries']
  lock_sleep   node['test']['lock_sleep'] if node['test']['lock_sleep']
end
