lib = File.expand_path('../..', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'capybara/rspec'
require 'fakeweb'
require 'rspec'
require 'openreqs'

configure do
  set :mongo, Mongo::Connection.new.db("openreqs-test")
  enable :raise_errors
  disable :show_exceptions
end

Capybara.app = Sinatra::Application

RSpec.configure do |config|
  config.before(:all) do
    @db = Capybara.app.mongo
    @db.connection.drop_database(@db.name)
    @docs, @requirements = @db["docs"], @db["requirements"]
  end
  
  config.after(:all) do
    db_sinatra = Capybara.app.mongo
    db_sinatra.connection.drop_database(db_sinatra.name)
    
    db_qu = Qu.backend.connection
    db_qu.connection.drop_database(db_qu.name)
  end
end
