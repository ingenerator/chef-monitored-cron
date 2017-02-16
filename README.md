monitored-cron cookbook
=======================
[![Build Status](https://travis-ci.org/ingenerator/chef-monitored-cron.png?branch=1.x)](https://travis-ci.org/ingenerator/chef-monitored-cron)

The `monitored-cron` cookbook supports logging, monitoring and alerting of cron
jobs rather than the traditional model of sending all their output to email.

Use `monitored-cron` when you want to:

* Log all the output of a cron job to syslog.
* Report an error if a cron writes to STDERR.
* Notify a webhook URL when a cron runs successfully (use with services like
  statuscake or  to verify that your crons are running).
* Prevent more than one instance of a particular cron running simultaneously (eg
  if a task runs longer than it's usual duration).


Requirements
------------
- Chef 12.18 or higher
- **Ruby 2.3 or higher**


Custom resources
----------------

## monitored_cron

```
# Minimum configuration showing defaults
monitored_cron 'backup' do
  command '/path/to/backup --src=/my/files --dest="s3://backup"'
  schedule       :time => :daily
  # user         'root'
  # require_lock false
end

# Or schedule with a cron expression
monitored_cron 'backup' do
  command '/path/to/backup --src=/my/files --dest="s3://backup"'
  schedule :hour => 12, :minute => 5
end

# Prevent overlapping execution of later crons if it slows down
# (this will cause a failure if a previous instance is still running when the
#  next cron interval is triggered)
monitored_cron 'backup' do
  command      '/path/to/backup --src=/my/files --dest="s3://backup"'
  schedule     :minute => '*'
  require_lock true
end

# Allow the cron to retry getting a lock 2 times over 30 seconds
monitored_cron 'backup' do
  command      '/path/to/backup --src=/my/files --dest="s3://backup"'
  schedule     :minute => '*'
  require_lock true
  lock_retries 2
  lock_sleep   15
end

# Ping an HTTP/s URL on successful completion
# The URL will not be called if the task outputs to stderr or exits nonzero
monitored_cron 'backup' do
  command      '/path/to/backup --src=/my/files --dest="s3://backup"'
  schedule     :minute => '*'
  notify_url   'http://my.monitoring/service'
end

# Report how long the task took to run in seconds
monitored_cron  'backup' do
  command       '/path/to/backup --src=/my/files --dest="s3://backup"'
  schedule      :minute => '*'
  notify_url    'http://my.monitoring/service?time=:runtime:'
  # will become http://my.monitoring/service?time=0.231
end
```

Testing
-------
See the [.travis.yml](.travis.yml) file for the current test scripts.


Contributing
------------
1. Fork the project
2. Create a feature branch corresponding to your change
3. Create specs for your change
4. Create your changes
4. Create a Pull Request on github

License & Authors
-----------------
- Author:: Andrew Coulton (andrew@ingenerator.com)

```text
Copyright 2017, inGenerator Ltd

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
