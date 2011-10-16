lib = File.expand_path('../..', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'capybara/rspec'
require 'rspec'
require 'openreqs'

set :environment, :test

Capybara.app = Sinatra::Application
