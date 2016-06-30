require 'logger'
require 'simplecov_setup'
require 'byebug'
require 'simple_job'

logger = Logger.new('log/test.log')
logger.level = Logger::DEBUG

SimpleJob::JobQueue.config(logger: logger)
AWS.config(logger: logger, log_level: :debug, access_key_id: 'access_key_id', secret_access_key: 'secret_access_key')
AWS.stub!

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_doubled_constant_names = true
    mocks.verify_partial_doubles = true
  end

  config.filter_run :f
  config.run_all_when_everything_filtered = true

  config.disable_monkey_patching!
  config.expose_dsl_globally = false

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.profile_examples = 10

  config.order = :random
  Kernel.srand config.seed
end
