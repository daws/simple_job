require 'socket'
require 'fog'

module SimpleJob
class SQSJobQueue < JobQueue

  # Registers this queue implementation with SimpleJob::JobQueue with identifier "sqs".
  register_job_queue 'sqs', self

  def self.config(options = {})
    @config ||= {
      :queue_prefix => ENV['SIMPLE_JOB_SQS_JOB_QUEUE_PREFIX'],
      :default_visibility_timeout => 60,
      :environment => (defined?(Rails) && Rails.env) || 'development',
      :cloud_watch_namespace => nil,
    }

    @config.merge!(options) if options

    raise 'must configure :queue_prefix using SQSJobQueue.config' if !@config[:queue_prefix]

    @config
  end

  def self.default_queue
    @default_queue || super
  end

  def self.define_queue(type, options = {})
    type = type.to_s

    options = {
      :visibility_timeout => config[:default_visibility_timeout],
      :default => false,
    }.merge(options)

    queue = self.new(type, options[:visibility_timeout])
    self.queues ||= {}
    self.queues[type] = queue

    @default_queue = queue if options[:default]
    
    queue
  end

  def self.get_queue(type, options = {})
    type = type.to_s
    (self.queues || {})[type] || super
  end

  def enqueue(message, options = {})
    raise("enqueue expects a raw string") unless message.is_a?(String)
    sqs_queue.send_message(message)
  end

  def poll(options = {}, &block)
    options = {
      :visibility_timeout => visibility_timeout,
      :attributes => [ :sent_at, :receive_count, :first_received_at ],
      :raise_exceptions => false,
    }.merge(options)

    message_handler = block || lambda do |definition, message|
      definition.execute
    end

    loop do
      last_message = nil
      current_job_type = ''
      current_start_milliseconds = 0
      begin
        sqs_queue.poll(options) do |message|
          last_message = message
          raw_message = JSON.parse(message.body)

          current_job_type = raw_message['type']
          current_start_milliseconds = get_milliseconds

          definition_class = JobDefinition.job_definition_class_for(raw_message['type'], raw_message['version'])
          raise('no definition found') if !definition_class
          definition = definition_class.new.from_json(message.body)
          message_handler.call(definition, message)

          log_execution(true, current_job_type, current_start_milliseconds)
        end
        return
      rescue SignalException, SystemExit => e
        logger.info "received #{e.class}; exiting poll loop and re-raising: #{e.message}"
        raise e
      rescue Exception => e
        log_execution(false, current_job_type, current_start_milliseconds)

        if options[:raise_exceptions]
          raise e
        else
          logger.error("unable to process message: #{e.message}")
          logger.error("message body: #{last_message && last_message.body}")
          logger.error(e.backtrace.join("\n  "))
        end
      end
    end
  end

  private

  class << self
    attr_accessor :queues
  end

  attr_accessor :queue_name, :sqs_queue, :visibility_timeout, :cloud_watch

  def initialize(type, visibility_timeout)
    sqs = ::AWS::SQS.new
    self.queue_name = "#{self.class.config[:queue_prefix]}-#{type}-#{self.class.config[:environment]}"
    self.sqs_queue = sqs.queues.create(queue_name)
    self.visibility_timeout = visibility_timeout
    self.cloud_watch = Fog::AWS::CloudWatch.new(
      :aws_access_key_id => AWS.config.access_key_id,
      :aws_secret_access_key => AWS.config.secret_access_key
    )
  end

  def logger
    JobQueue.config[:logger]
  end

  def get_milliseconds
    (Time.now.to_f * 1000).round
  end

  def log_execution(successful, job_type, start_milliseconds)
    if self.class.config[:cloud_watch_namespace]
      timestamp = DateTime.now.to_s
      environment = self.class.config[:environment]
      hostname = Socket.gethostbyname(Socket.gethostname).first
      execution_time = get_milliseconds - start_milliseconds
      dimensions = [
        { 'Name' => 'Environment', 'Value' => environment }, 
        { 'Name' => 'SQSQueueName', 'Value' => queue_name },
        { 'Name' => 'JobType', 'Value' => job_type },
        { 'Name' => 'Host', 'Value' => hostname },
      ]

      cloud_watch.put_metric_data(self.class.config[:cloud_watch_namespace], [
        {
          'MetricName' => 'ExecutionCount',
          'Timestamp' => timestamp,
          'Unit' => 'Count',
          'Value' => 1,
          'Dimensions' => dimensions
        },
        {
          'MetricName' => 'SuccessCount',
          'Timestamp' => timestamp,
          'Unit' => 'Count',
          'Value' => successful ? 1 : 0,
          'Dimensions' => dimensions
        },
        {
          'MetricName' => 'ErrorCount',
          'Timestamp' => timestamp,
          'Unit' => 'Count',
          'Value' => successful ? 0 : 1,
          'Dimensions' => dimensions
        },
        {
          'MetricName' => 'ExecutionTime',
          'Timestamp' => timestamp,
          'Unit' => 'Milliseconds',
          'Value' => execution_time,
          'Dimensions' => dimensions
        },
      ] )
    end
  end

end
end

