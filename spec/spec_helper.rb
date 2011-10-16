lib = File.expand_path('../..', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'capybara/rspec'
require 'rspec'
require 'openreqs'

configure do
  set :mongo, Mongo::Connection.new.db("openreqs-test")
end


Capybara.app = Sinatra::Application

RSpec.configure do |config|
  config.before(:all) do
    @db = Capybara.app.mongo
    @db.connection.drop_database(@db.name)
    @docs, @requirements = @db["docs"], @db["requirements"]
  end
end
