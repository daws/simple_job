require 'logger'
require 'aws-sdk'

# Requires the aws-sdk gem, which must be initialized for this API to be capable of queuing requests.
#
# Synopsis:
#
#  include SimpleJob
#
#  JobQueue::DEFAULT.poll do |message|
#    puts message
#  end
#
# == Creating a queue implementation
#
# To create a new queue implementation, just extend the SimpleJob::JobQueue
# class, and call the register_job_queue declaration with an identifier. The
# class must implement the get_queue class method and the enqueue/poll instance
# methods to fulfill the interface. The default_queue method may be overridden
# to set a default queue.
#
# Example:
# 
#  class ArrayQueue < SimpleJob::JobQueue
#    register_job_queue 'array', self
#
#    include Singleton
#    default self.instance
#  
#    def self.get_queue(type, options = {})
#      instance
#    end
#    def enqueue(message, options = {})
#      queue << message
#    end
#    def poll(options = {}, &block)
#      options = {
#        :interval => 1
#      }.merge(options)
#      loop do
#        message = queue.shift
#        yield(message) if message
#        Kernel.sleep(options[:interval])
#      end
#    end
#    private
#    def queue
#      @queue ||= []
#    end
#  end
#
# Then you can use the new queue implementation by passing its identifier to
# JobQueue.config:
#
#  SimpleJob::JobQueue.config :implementation => 'array'
module SimpleJob
class JobQueue

  def self.register_job_queue(identifier, klass)
    @@registered_job_queues ||= {}
    @@registered_job_queues[identifier.to_s] = klass
  end

  def self.config(options = {})
    @config ||= {
      :implementation => 'sqs',
      :logger => default_logger,
    }
    @config.merge!(options) if options
    @config
  end

  def self.[](type, options = {})
    queue_class.get_queue(type, options)
  end

  def self.default_queue
    raise "default queue not defined"
  end

  def self.default
    queue_class.default_queue
  end

  def self.get_queue(type, options = {})
    raise "queue with type #{type} not defined"
  end

  def self.queue_class
    @@registered_job_queues[config[:implementation].to_s]
  end

  def enqueue(message, options = {})
    raise NotImplementedError
  end

  def poll(options = {}, &block)
    raise NotImplementedError
  end

  private

  def self.default_logger
    return Rails.logger if defined?(Rails)
    logger = Logger.new(STDERR)
    logger.level = Logger::INFO
    logger
  end

end
end
