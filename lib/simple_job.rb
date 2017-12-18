# frozen_string_literal: true

module SimpleJob
  autoload :JobDefinition, 'simple_job/job_definition'
  autoload :JobQueue, 'simple_job/job_queue'
end

require 'simple_job/test_job_queue'
require 'simple_job/sqs_job_queue'
