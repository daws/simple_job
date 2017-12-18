source 'https://rubygems.org'

gemspec

group :rake do
  gem 'simple_gem', require: 'tasks/simple_gem'
end

group :test do
  gem 'rspec', '~> 3.7'
  gem 'simplecov'
  gem 'byebug'

  ['activemodel', 'activesupport'].each do |rails_gem|
    gem rails_gem, '~> 5.0.3'
  end
end

