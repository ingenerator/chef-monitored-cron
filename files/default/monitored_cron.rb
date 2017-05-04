#!/usr/bin/env ruby
#
# This program wraps a child executable in use as a cron job, and:
#  * Diverts all output to syslog (stdout => debug, stderr => warning)
#  * Optionally, requires a lock so that only one instance of the job can run
#    at any one time
#  * Logs a confirmation message to syslog when the task successfully completes,
#    or logs an error if it fails (nonzero exit or any output to stderr)
#  * Optionally, pings an HTTP/s URL when the task successfully completes - this
#    can be templated to inclde the runtime in seconds eg as a GET parameter
#
# It takes a single command argument, which is a path to a JSON job file with
# configuration for the task.
#
# The job conig looks something like
#
#   {
#     "command": "/path/to/script with --some=arguments && anything 'that works in shell'",
#     "notify":  {"url": "https://my.tracker/ac823-ado?time=:runtime:"},
#     "locking": {"lockrun": "/path/to/lockrun", "lock_dir": "/var/run/", "retries": 2, "sleep": 5}
#   }
#
#
# Log messages use the LOG_CRON syslog facility and a program name calculated
# the basename of the job config file provided
#
# Author::    Andrew Coulton (mailto:andrew@ingenerator.com)
# Copyright:: Copyright (c) 2017 inGenerator Ltd
# License::   Apache 2.0
require 'syslog/logger'
require 'json'
require 'open3'
require 'net/http'

# This class is responsible for executing the process
class MonitoredCronRunner
  # Maximum buffer to read from stdout / stderr in one go
  READ_SIZE = 4096

  # Maximum time to sleep waiting for new child process output
  # The longer this is, the more chance that you will have to wait if a process
  # finishes without printing any additional output
  DEFAULT_READ_TIMEOUT = 5

  # Thrown if the job configuration is missing or invalid
  class InvalidConfigurationError < RuntimeError
    def initialize(file, source_error)
      super(
        "Invalid job config `#{file}`: [#{source_error.class.name}] #{source_error.message}"
      )
    end
  end

  # Executes the wrapper and runs the command
  #
  # * +job_file+ - path to the job JSON config file
  def self.run(job_file)
    new(job_file).instance_eval { run }
  end

  private

  # Initialises the wrapper
  #
  # * +job_file+ - path to the job JSON config file
  def initialize(job_file)
    @job_file       = job_file
    @job_name       = File.basename(job_file, '.json')
    @syslog_program = 'cron-' + @job_name
    @config         = nil
    @start_time     = nil
    @end_time       = nil
    @had_stderr     = false
  end

  def run
    @config         = load_config
    @start_time     = Time.now
    result          = run_command(build_wrapped_command)
    @end_time       = Time.now
    report_status(result)
  rescue InvalidConfigurationError => err
    log(Syslog::LOG_ALERT, err.message)
  rescue SystemCallError => err
    log(Syslog::LOG_ALERT, 'Failed to start: %s', err.message)
  end

  def load_config
    config = JSON.parse(File.read(@job_file))
    validate_config(config)
    return config
  rescue Exception => err
    raise InvalidConfigurationError.new(@job_file, err)
  end

  def validate_config(config)
    raise ArgumentError, 'No command specified' unless config['command']
    raise ArgumentError, 'Command is not a string' unless config['command'].is_a? String

    validate_notify_url(config['notify']['url']) if config['notify']
    validate_locking(config['locking']) if config['locking']
  end

  def validate_notify_url(url)
    raise  ArgumentError, 'notify.url is not a string' unless url.is_a? String
    unless url =~ URI.regexp(%w(http https))
      raise ArgumentError, "`#{url}` is not a valid notify URL"
    end
  end

  def validate_locking(config)
    raise ArgumentError, 'locking.lockrun path required for locking' unless config['lockrun']
    raise ArgumentError, 'locking.lock_dir required for locking' unless config['lock_dir']
    if config['retries']
      raise ArgumentError, 'locking.sleep required if locking.retries used' unless config['sleep']
      raise ArgumentError, 'locking.retries is not an integer' unless config['retries'].is_a? Integer
      raise ArgumentError, 'locking.sleep is not an integer' unless config['sleep'].is_a? Integer
    end
  end

  # Builds the actual command to execute based on the job's `command` config
  # and any locking configuration which will be used to prefix the main command
  # with the arguments required to run it inside lockrun.
  def build_wrapped_command
    command = @config['command']

    if @config['locking']
      command = [
        @config['locking']['lockrun'],
        "--lockfile=#{lockrun_lockfile}",
        lockrun_retry_args,
        '--',
        @config['command']
      ].compact.join(' ')
    end

    command
  end

  # The path to the lockfile lockrun should use
  def lockrun_lockfile
    dir = @config['locking']['lock_dir'].chomp('/')
    "#{dir}/cron-#{@job_name}.lock"
  end

  def lockrun_retry_args
    return nil unless @config['locking']['retries']
    format(
      '--retries=%d --sleep=%d',
      @config['locking']['retries'],
      @config['locking']['sleep']
    )
  end

  def run_command(command)
    exit_status = nil

    Open3.popen3(command) do |_stdin, stdout, stderr, wait_thr|
      while wait_thr.alive?
        log_command_output(stdout, stderr, DEFAULT_READ_TIMEOUT)
      end
      log_command_output(stdout, stderr, 1) # Capture any final output
      exit_status = wait_thr.value
    end

    raise 'Did not capture exit status from command' unless exit_status
    exit_status
  end

  # Captures all command output, sleeping whenever there is nothing new to read
  def log_command_output(stdout, stderr, timeout)
    output = read_pipe_lines(stdout, stderr, timeout)

    output[:stdout].each do |line|
      log(Syslog::LOG_DEBUG, line.gsub(/%/, '%%'))
    end

    output[:stderr].each do |line|
      @had_stderr = true
      log(Syslog::LOG_WARNING, line.gsub(/%/, '%%'))
    end
  end

  # Reads the current content of stdout and stderr (if any) as an array of lines
  # for each stream
  def read_pipe_lines(stdout, stderr, timeout)
    result = { stdout: [], stderr: [] }
    ready_pipes = IO.select([stdout, stderr], nil, nil, timeout)
    result[:stdout] = read_buffer(stdout) if pipe_ready?(ready_pipes, stdout)
    result[:stderr] = read_buffer(stderr) if pipe_ready?(ready_pipes, stderr)
    result
  end

  def pipe_ready?(ready_pipes, pipe)
    ready_pipes && ready_pipes.first.include?(pipe)
  end

  def read_buffer(pipe)
    buffer = ''
    begin
      while chunk = pipe.read_nonblock(READ_SIZE)
        buffer << chunk
      end
    rescue Errno::EAGAIN
    rescue EOFError
      # Empty pipe, ignore this here so we can drop back to check if the
      # process is still running and/or wait for further output
    end

    buffer.split("\n")
  end

  # Actually logs the output to syslog
  # Falls back to logging to console if there are any problems writing to the
  # syslog, in the hope cron might be able to email it to someone useful
  def log(level, format_string, *format_args)
    @syslog ||= Syslog.open(@syslog_program, Syslog::LOG_CONS, Syslog::LOG_CRON)
    @syslog.log(level, format_string, *format_args)

    # Rather crude test hook to clone syslog output to the console for integration
    # testing
    if ENV['MONITORED_CRON_TEST']
      puts format(
        '%s: [%s] %s',
        @syslog_program,
        level,
        format(format_string, *format_args)
      )
    end
  end

  # Handle the task exit status and report overall state
  def report_status(exit_status)
    if !exit_status.success?
      log(Syslog::LOG_ERR, 'Failed with exit code %d after %ss', exit_status.exitstatus, task_runtime_seconds)
    elsif @had_stderr
      log(Syslog::LOG_ERR, 'Displayed errors but exited 0 after %ss', task_runtime_seconds)
    else
      log(Syslog::LOG_INFO, 'Ran successfully in %ss', task_runtime_seconds)
      ping_success_webhook
    end
  end

  def task_runtime_seconds
    runtime = @end_time - @start_time
    format('%.3f', runtime)
  end

  def ping_success_webhook
    return unless @config['notify']

    url = @config['notify']['url'].sub(':runtime:', task_runtime_seconds)
    Net::HTTP.get(URI(url))
    log(Syslog::LOG_INFO, 'Pinged %s', url)
  end
end # /MonitoredCronRunner

# This section is the script `main` executable. The conditional is to make it run
# if you are executing this script directly, but not if the class is being included
# eg from rspec for testing
if $PROGRAM_NAME == __FILE__
  begin
    MonitoredCronRunner.run(ARGV[0])
  rescue Exception => err
    # Rescuing Exception is usually considered bad practice, but we want to do
    # as much as we can to try and get any and all issues reported via Syslog
    # since it's likely anything printed to console / elsewhere won't make it
    # to the end user.
    # If we're not able to log to syslog here then it will spit out output and
    # hopefully the cron daemon will be able to email it to someone that can fix
    # it.
    Syslog.close if Syslog.opened?
    Syslog.open('monitored-cron', Syslog::LOG_CONS | Syslog::LOG_NDELAY, Syslog::LOG_CRON)
    Syslog.log(
      Syslog::LOG_EMERG,
      'Unexpected exception [%s] %s in %s',
      err.class.name,
      err.message,
      err.backtrace.first
    )
  end
end
