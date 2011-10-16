require 'spec_helper'

describe "An empty Openreqs application", :type => :request do
  it "is empty" do
    @requirements.find.to_a.should be_empty
    @docs.find.to_a.should be_empty
  end
  
  it "creates an empty index document on first access" do
    visit '/'
    @docs.find.to_a.should have(1).items
    index = @docs.find_one
    index.should include("date", "_content", "_name")
    index["_name"].should == "index"
    index["_content"].should be_empty
    index["date"].should be_within(60).of(Time.now)
  end
end

describe "An Openreqs application", :type => :request do
  it "does not creates an empty index document if it already exists" do
    visit '/'
    visit '/'
    
    @docs.find.to_a.should have(1).items
  end
  
  it "redirects '' to '/'" do
    visit ''
    current_path.should == "/"
  end
  
  it "returns 'page not found' for unknown pages" do
    visit '/unknown'
    page.status_code.should == 404
  end
  
  it "returns 'page not found' for unknown documents" do
    visit '/d/unknown'
    page.status_code.should == 404
  end
  
  it "returns 'page not found' for unknown requirements" do
    visit '/r/unknown'
    page.status_code.should == 404
  end
end
