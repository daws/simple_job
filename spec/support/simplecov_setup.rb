# frozen_string_literal: true

require 'simplecov'

SimpleCov.start do
  track_files 'lib/**/*.rb'

  add_filter 'bundle/'
  add_filter 'spec/'
  add_filter 'lib/simple_job/version'

  minimum_coverage 82
end
