lib = File.expand_path('../..', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'capybara/rspec'
require 'rspec'
require 'openreqs'

set :environment, :test

Capybara.app = Sinatra::Application

RSpec.configure do |config|
  config.before(:all) do
    @db = Capybara.app.mongo
    @db.connection.drop_database("openreqs")
    @docs, @requirements = @db["docs"], @db["requirements"]
  end
end
