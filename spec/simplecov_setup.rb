require 'simplecov'

SimpleCov.start do
  track_files 'lib/**/*.rb'

  add_filter 'bundle/'
  add_filter 'spec/'

  minimum_coverage 77
end
