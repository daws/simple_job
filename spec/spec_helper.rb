# frozen_string_literal: true

require 'byebug'
require 'support/vcr_setup'
require 'support/simplecov_setup'
require 'simple_job'

require 'logger'
logger = Logger.new('log/test.log')
logger.level = Logger::DEBUG

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_doubled_constant_names = true
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.filter_run :f
  config.run_all_when_everything_filtered = true

  config.disable_monkey_patching!
  config.expose_dsl_globally = false

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.profile_examples = 10

  config.order = :random
  Kernel.srand config.seed
end
