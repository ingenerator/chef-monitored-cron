#!/usr/bin/env ruby
require 'syslog/logger'
require 'json'
require 'open3'
require 'net/http'

class MonitoredCronRunner
  READ_WAIT_TIME = 0.01
  READ_SIZE = 4096
  DEFAULT_READ_TIMEOUT = 600

  class InvalidConfigurationError < RuntimeError
    def initialize(file, source_error)
      super(
        "Invalid job config `#{file}`: [#{source_error.class.name}] #{source_error.message}"
      )
    end
  end

  class CommandFailedError < RuntimeError
  end

  class CommandErrorOutputError < RuntimeError
  end

  def self.run(job_file)
    new(job_file).instance_eval { run }
  end

  private

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
    syslog.unknown(err.message)
  rescue SystemCallError => err
    syslog.unknown('Failed to start: ' + err.message)
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

  def log_command_output(stdout, stderr, timeout)
    output = read_pipe_lines(stdout, stderr, timeout)

    output[:stdout].each do |line|
      syslog.debug(line)
    end

    output[:stderr].each do |line|
      @had_stderr = true
      syslog.error(line)
    end
  end

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
      # Empty pipe, wait till next time
    end

    buffer.split("\n")
  end

  def syslog
    # FACILITY
    @syslog ||= Syslog::Logger.new(@syslog_program)
  end

  def report_status(exit_status)
    if !exit_status.success?
      syslog.fatal("Failed with exit code #{exit_status.exitstatus} after " + task_runtime_seconds + 's')
    elsif @had_stderr
      syslog.fatal('Displayed errors but exited 0 after ' + task_runtime_seconds + 's')
    else
      syslog.info('Ran successfully in ' + task_runtime_seconds + 's')
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
    syslog.info('Pinged '+url)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    MonitoredCronRunner.run(ARGV[0])
  rescue Exception => err
    syslog = Syslog::Logger.new('monitored-cron')
    syslog.unknown("Unexpected exception [#{err.class.name}] #{err.message} in {#{err.backtrace.first}}")
  end
end
