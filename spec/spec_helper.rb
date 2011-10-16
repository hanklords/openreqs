lib = File.expand_path('../..', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'capybara/rspec'
require 'openreqs'
