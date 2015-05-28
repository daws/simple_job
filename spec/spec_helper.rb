require 'logger'

require 'bundler'
Bundler.require(:default, :test)

require 'simple_job'

logger = Logger.new('log/test.log')
logger.level = Logger::DEBUG

SimpleJob::JobQueue.config(logger: logger)
AWS.config(logger: logger, log_level: :debug)
