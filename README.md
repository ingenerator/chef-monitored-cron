monitored-cron cookbook
=======================
[![Build Status](https://travis-ci.org/ingenerator/chef-monitored-cron.png?branch=1.x)](https://travis-ci.org/ingenerator/chef-monitored-cron)

The `monitored-cron` cookbook supports logging, monitoring and alerting of cron
jobs rather than the traditional model of sending all their output to email.

Use `monitored-cron` when you want to:

* ~~Log all the output of a cron job.~~
* ~~Report an error if a cron writes to STDERR.~~
* ~~Report an error based on analysing the cron output.~~
* ~~Notify a webhook URL when a cron runs (use with services like statuscake or
  pushmon to verify that your crons are running).~~
* ~~Capture a cron's output or status to syslog.~~
* ~~Prevent more than one instance of a particular cron running simultaneously (eg
  if a task runs longer than it's usual duration).~~


Requirements
------------
- Chef 12.18 or higher
- **Ruby 2.3 or higher**


Custom resources
----------------

## monitored_cron

tbc


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
