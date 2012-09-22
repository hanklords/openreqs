lib = File.expand_path('../../lib', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'capybara/rspec'
require 'fakeweb'
require 'rspec'
require 'openreqs'

Qu.configure do |c|
  c.connection = Mongo::Connection.new.db("openreqs-test-qu")
end

Openreqs.enable :raise_errors
Openreqs.disable :show_exceptions

Capybara.app = Openreqs.new {|app| app.db_name = "openreqs-test"}
FakeWeb.allow_net_connect = false

RSpec.configure do |config|
  config.before(:all) do
    @db = Mongo::Connection.new.db("openreqs-test")
    @db.connection.drop_database(@db.name)
    @docs  = @db["docs"]
  end
  
  config.after(:all) do
    db_sinatra = Mongo::Connection.new.db("openreqs-test")
    db_sinatra.connection.drop_database(db_sinatra.name)
    
    db_qu = Qu.backend.connection
    db_qu.connection.drop_database(db_qu.name)
  end
end
