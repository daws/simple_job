# frozen_string_literal: true

require 'socket'
require 'aws-sdk-sqs'
require 'aws-sdk-cloudwatch'

module SimpleJob
  # A SimpleJob::JobQueue implementation that uses AWS SQS
  class SQSJobQueue < JobQueue
    DEFAULT_POLL_INTERVAL = 1

    # Registers this queue implementation with SimpleJob::JobQueue with identifier "sqs".
    register_job_queue 'sqs', self

    def self.config(options = {})
      @config ||= {
        queue_prefix: ENV['SIMPLE_JOB_SQS_JOB_QUEUE_PREFIX'],
        default_visibility_timeout: 60,
        environment: (defined?(Rails) && Rails.env) || 'development',
        cloud_watch_namespace: nil
      }

      @config.merge!(options) if options

      unless @config[:queue_prefix]
        raise ArgumentError, 'must configure :queue_prefix using SQSJobQueue.config'
      end

      @config
    end

    def self.default_queue
      @default_queue || super
    end

    # Sets up an SQS queue, using the given type as a unique identifier for the name.
    #
    # A :visibility_timeout option may be passed to override the visibility timeout
    # that is used when polling the queue.
    #
    # The :asynchronous_execute option, if set to true, will cause the poll method to
    # parse and immediately accept each message (if it's validly formatted). It will
    # then fork and execute the proper job in a separate process. This can be
    # used when you have long-running jobs that will exceed the visibility timeout,
    # and it is not critical that they be retried when they fail.
    #
    # You may pass an :accept_nested_definition option with a string value to allow this
    # queue to accept messages where the body is nested within a hash entry. This
    # facilitates easy processing of SNS and AutoScaling messages. For example, if you
    # pass this option:
    #
    #   accept_nested_definition: 'NotificationMetadata'
    #
    # Then you can put a job body into the NotificationMetadata of an AutoScaling
    # notification:
    #
    #   { "AutoScalingGroupName": "some_name", "Service": "AWS Auto Scaling" ...
    #     "NotificationMetadata": "{\"type\":\"my_job\",\"version\":\"1\"}" }
    #
    # Then the queue will attempt to process incoming messages normally, but if it
    # encounters a message missing a type and version, it will check the value
    # passed into accept_nested_definition before failing.
    def self.define_queue(type, options = {})
      type = type.to_s

      options = {
        visibility_timeout: config[:default_visibility_timeout],
        asynchronous_execute: false,
        default: false
      }.merge(options)
      make_default = options.delete(:default)

      queue = new(type, options)
      self.queues ||= {}
      self.queues[type] = queue

      @default_queue = queue if make_default

      queue
    end

    def self.get_queue(type, options = {})
      type = type.to_s
      (self.queues || {})[type] || super
    end

    def enqueue(message, options = {})
      raise ArgumentError 'enqueue expects a raw string' unless message.is_a?(String)
      sqs_queue.send_message(options.merge(message_body: message, queue_url: sqs_queue_url))
    end

    # Polls the queue, matching incoming messages with registered jobs, and
    # executing the proper job/version.
    #
    # If called without a block, it will simply call the #execute method of the
    # matched job. A block may be passed to add custom logic, but in this case
    # the caller is responsible for calling #execute. The block will be passed
    # two arguments, the matching job definition (already populated with the
    # contents of the message) and the raw AWS message.
    #
    # The #execute method MAY have a parameter, which will be populated with
    # the raw AWS::SQS::ReceivedMessage object if it exists.
    #
    # The queue's configured visibility timeout will be used unless the
    # :visibility_timeout option is passed (as a number of seconds).
    #
    # By default, the message's 'sent_at', 'receive_count', and
    # 'first_received_at' attributes will be populated in the AWS message, but
    # this may be overridden by passing an array of symbols to the :attributes
    # option.
    #
    # By default, errors during job execution or message polling will be logged
    # and the polling will continue, but that behavior may be changed by setting
    # the :raise_exceptions option to true.
    #
    # By defult, this method will poll indefinitely. If you pass an :idle_timeout
    # option, the polling will stop and this method will return if that number
    # of seconds passes without receiving a message. In both cases, the method
    # will safely complete processing the current message and return if a HUP,
    # INT, or TERM signal is sent to the process.
    #
    # You may also pass a :max_executions option (as an integer), in which case
    # the poll method will poll that many times and then exit.
    #
    # If poll_interval is set, polling will pause for poll_interval seconds when there are no
    # available messages.  If always_sleep is set to true, then polling will pause
    # after every message is received, even if there are more available messages.
    #
    # Note that this method will override any signal handlers for the HUP, INT,
    # or TERM signals during its execution, but the previous handlers will be
    # restored once the method returns.
    def poll(options = {}, &block)
      options = {
        visibility_timeout: visibility_timeout,
        attributes: %i[sent_at receive_count first_received_at],
        raise_exceptions: false,
        idle_timeout: nil,
        poll_interval: DEFAULT_POLL_INTERVAL,
        max_executions: nil,
        always_sleep: false
      }.merge(options)

      sqs_receive_options = {
        visibility_timeout: options[:visibility_timeout],
        idle_timeout: options[:idle_timeout],
        queue_url: sqs_queue_url,
        max_number_of_messages: 1
      }

      message_handler = block || lambda do |definition, message|
        execute_method = definition.method(:execute)
        arguments = []
        arguments << message if execute_method.arity >= 1
        execute_method.call(*arguments)
      end

      exit_next = false

      logger.debug 'trapping terminate signals with function to exit loop'
      signal_exit = lambda do |*_args|
        logger.info 'caught signal to shutdown; finishing current message and quitting...'
        exit_next = true
      end
      previous_traps = {}
      %w[HUP INT TERM].each do |signal|
        previous_traps[signal] = Signal.trap(signal, signal_exit)
      end

      last_message_at = Time.now.utc

      max_executions = options[:max_executions]
      loop do
        break if max_executions && (max_executions <= 0)
        last_message = nil
        last_definition = nil
        current_start_milliseconds = get_milliseconds
        current_job_type = 'unknown'
        begin
          sqs_queue.receive_message(sqs_receive_options).messages.each do |message|
            message_body = get_message_body(message)
            raw_message = JSON.parse(message_body)

            if raw_message['type'] && raw_message['version']
              last_message = message
              last_message_at = Time.now.utc
              current_job_type = raw_message['type']
              definition_class = JobDefinition.job_definition_class_for(
                raw_message['type'], raw_message['version']
              )

              raise StandardError, 'no definition found' unless definition_class

              if definition_class.max_attempt_count &&
                 (message.receive_count > definition_class.max_attempt_count)
                raise StandardError, 'max attempt count reached'
              end

              definition = definition_class.new.from_json(message_body)
              last_definition = definition

              # NOTE: only executes if asynchronous_execute is false (message will be re-enqueued
              # after vis. timeout if this fails or runs too long)
              message_handler.call(definition, message) unless asynchronous_execute
            else
              logger.info("ignoring invalid message: #{message_body}")
            end
          end

          # NOTE: only executes if asynchronous_execute is set (after message has been confirmed)
          if asynchronous_execute && last_message
            pid = fork
            if pid
              # in parent
              Process.detach pid
            else
              # in child
              begin
                message_handler.call(last_definition, last_message)
                delete_message(last_message)
                log_execution(true, last_message, current_job_type, current_start_milliseconds)
              rescue StandardError => e
                logger.error("error executing asynchronous job: #{e.message}")
                logger.error e.backtrace.join("\n  ")
              end
              exit # rubocop:disable Rails/Exit
            end
          else
            delete_message(last_message)
            log_execution(true, last_message, current_job_type, current_start_milliseconds)
          end

          if options[:idle_timeout] && ((Time.now.utc - last_message_at) > options[:idle_timeout])
            break
          end

          if options[:always_sleep] || !last_message
            Kernel.sleep(options[:poll_interval]) unless options[:poll_interval].zero?
          end
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          begin
            log_execution(false, last_message, current_job_type, current_start_milliseconds)
          rescue StandardError
            nil
          end

          raise e if options[:raise_exceptions]

          logger.error("unable to process message: #{e.message}")
          logger.error("message body: #{last_message&.body}")
          logger.error(e.backtrace.join("\n  "))
        end
        max_executions -= 1 if max_executions
        break if exit_next
      end

      logger.debug 'restoring previous signal traps'
      previous_traps.each do |signal, command|
        Signal.trap(signal, command)
      end

      logger.info 'shutdown successful'
    end

    def delete_message(message)
      return unless message

      sqs_queue.delete_message(queue_url: sqs_queue_url, receipt_handle: message.receipt_handle)
    end

    private

    class << self
      attr_accessor :queues
    end

    attr_accessor :visibility_timeout, :asynchronous_execute, :accept_nested_definition,
                  :queue_name, :cloud_watch, :sqs_queue, :sqs_queue_url

    def initialize(type, visibility_timeout:, asynchronous_execute:, accept_nested_definition: nil)
      self.visibility_timeout = visibility_timeout
      self.asynchronous_execute = asynchronous_execute
      self.accept_nested_definition = accept_nested_definition

      self.queue_name = "#{self.class.config[:queue_prefix]}-#{type}-" \
        "#{self.class.config[:environment]}"
      self.cloud_watch = Aws::CloudWatch::Client.new
      self.sqs_queue = Aws::SQS::Client.new
      self.sqs_queue_url = sqs_queue.create_queue(queue_name: queue_name).queue_url
    end

    def logger
      JobQueue.config[:logger]
    end

    def get_milliseconds(time = Time.now.utc)
      (time.to_f * 1000).round
    end

    # localhost throws an error when calling Socket.gethostbyname, don't call it in dev & test
    def hostname
      @hostname ||= if %w[development test].include?(self.class.config[:environment])
                      Socket.gethostname
                    else
                      Socket.gethostbyname(Socket.gethostname).first
                    end
    end

    def log_execution(successful, message, job_type, start_milliseconds)
      return unless self.class.config[:cloud_watch_namespace]

      timestamp = Time.now.utc.iso8601

      message_dimensions = [
        { name: 'Environment', value: self.class.config[:environment] },
        { name: 'SQSQueueName', value: queue_name },
        { name: 'Host', value: hostname }
      ]

      job_dimensions = message_dimensions + [
        { name: 'JobType', value: job_type }
      ]

      metric_data = [
        {
          metric_name: 'MessageCheckCount',
          timestamp: timestamp,
          unit: 'Count',
          value: 1,
          dimensions: message_dimensions
        },
        {
          metric_name: 'MessageReceivedCount',
          timestamp: timestamp,
          unit: 'Count',
          value: message ? 1 : 0,
          dimensions: message_dimensions
        },
        {
          metric_name: 'MessageMissCount',
          timestamp: timestamp,
          unit: 'Count',
          value: message ? 0 : 1,
          dimensions: message_dimensions
        }
      ]

      if message
        now = get_milliseconds

        metric_data.concat([
                             {
                               metric_name: 'ExecutionCount',
                               timestamp: timestamp,
                               unit: 'Count',
                               value: 1,
                               dimensions: job_dimensions
                             },
                             {
                               metric_name: 'SuccessCount',
                               timestamp: timestamp,
                               unit: 'Count',
                               value: successful ? 1 : 0,
                               dimensions: job_dimensions
                             },
                             {
                               metric_name: 'ErrorCount',
                               timestamp: timestamp,
                               unit: 'Count',
                               value: successful ? 0 : 1,
                               dimensions: job_dimensions
                             },
                             {
                               metric_name: 'ExecutionTime',
                               timestamp: timestamp,
                               unit: 'Milliseconds',
                               value: now - start_milliseconds,
                               dimensions: job_dimensions
                             }
                           ])

        if successful
          attributes = message.attributes
          sent_timestamp = attributes['SentTimestamp'].to_i
          receive_count = attributes['ApproximateReceiveCount'].to_i
          metric_data.concat([
                               {
                                 metric_name: 'TimeToCompletion',
                                 timestamp: timestamp,
                                 unit: 'Milliseconds',
                                 value: now - sent_timestamp,
                                 dimensions: job_dimensions
                               },
                               {
                                 metric_name: 'ExecutionAttempts',
                                 timestamp: timestamp,
                                 unit: 'Count',
                                 value: receive_count,
                                 dimensions: job_dimensions
                               }
                             ])
        end
      end

      cloud_watch.put_metric_data(
        namespace: self.class.config[:cloud_watch_namespace], metric_data: metric_data
      )
    end

    def get_message_body(message)
      result = message.body
      message_hash = JSON.parse(result)

      if (!message_hash.key?('type') || !message_hash.key?('version')) && accept_nested_definition
        result = message_hash[accept_nested_definition]
      end

      result || '{}'
    end
  end
end
