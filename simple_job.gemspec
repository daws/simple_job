# frozen_string_literal: true

require_relative 'lib/simple_job/version'

Gem::Specification.new do |s|
  # definition
  s.name = 'simple_job'
  s.version = SimpleJob::VERSION

  # details
  s.license = 'Nonstandard'
  s.summary = 'Support classes and modules for executable jobs.'
  s.description = 'Contains libraries that support defining, queueing, and executing jobs.'
  s.authors = ['David Dawson']
  s.email = 'daws23@gmail.com'
  s.homepage = 'https://www.stashrewards.com'

  # paths and files
  s.files = Dir['lib/**/*.rb', 'README.rdoc', 'CHANGELOG.rdoc', 'LICENSE.txt']
  s.require_paths = ['lib']

  # dependencies
  s.add_dependency 'activemodel', '> 4.2', '< 6'
  s.add_dependency 'activesupport', '> 4.2', '< 6'
  s.add_dependency 'aws-sdk-sqs', '~> 1'
  s.add_dependency 'aws-sdk-cloudwatch', '~> 1'
end
