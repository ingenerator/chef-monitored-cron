name 'monitored-cron'
maintainer 'Andrew Coulton'
maintainer_email 'andrew@ingenerator.com'
license 'Apache 2.0'
description 'Wraps cron jobs to provide logging, remote monitoring and alerting'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version '0.1.1'
issues_url 'https://github.com/ingenerator/chef-monitored-cron/issues'
source_url 'https://github.com/ingenerator/chef-monitored-cron'

%w(ubuntu).each do |os|
  supports os
end
