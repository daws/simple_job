require File.expand_path(File.join(File.dirname(__FILE__), 'lib', 'simple_job', 'version'))

Gem::Specification.new do |s|

  # definition
  s.name = %q{simple_job}
  s.version = SimpleJob::VERSION

  # details
  s.date = %q{2012-01-10}
  s.summary = %q{Support classes and modules for executable jobs.}
  s.description = %q{Contains libraries that support defining, queueing, and executing jobs.}
  s.authors = [ 'David Dawson' ]
  s.email = %q{daws23@gmail.com}
  s.homepage = %q{https://github.com/daws/simple_job}
  s.require_paths = [ 'lib' ]
  
  # documentation
  s.has_rdoc = true
  s.extra_rdoc_files = %w( README.rdoc CHANGELOG.rdoc LICENSE.txt )
  s.rdoc_options = %w( --main README.rdoc )

  # files to include
  s.files = Dir[ 'lib/**/*.rb', 'README.rdoc', 'CHANGELOG.rdoc', 'LICENSE.txt' ]

  # dependencies
  s.add_dependency 'activemodel', '>= 3.0'
  s.add_dependency 'activesupport', '>= 3.0'
  s.add_dependency 'aws-sdk-v1', '~> 1.2'
  s.add_dependency 'fog', '~> 1.1'

end
