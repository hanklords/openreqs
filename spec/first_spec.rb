require 'spec_helper'

describe "An empty Openreqs application", :type => :request do
  before(:all) do
    @db = page.app.mongo
    @db.connection.drop_database("openreqs")
    @docs, @requirements = @db["docs"], @db["requirements"]
  end
  
  it "creates an empty index page on first access" do
    visit '/'
    @docs.find.to_a.should have(1).items
    index = @docs.find_one
    index.should include("date", "_content", "_name")
    index["_name"].should == "index"
    index["_content"].should be_empty
    index["date"].should be_within(60).of(Time.now)
  end
end
