# Installs the monitored-cron wrapper and dependencies needed for a
# monitored_cron resource
#
# Author::  Andrew Coulton (<andrew@ingenerator.com>)
# Copyright 2017, inGenerator Ltd

include_recipe 'monitored-cron::install'
include_recipe 'monitored-cron::install_lockrun'
