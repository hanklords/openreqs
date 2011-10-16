require "spec_helper"

describe "An empty Openreqs application", :type => :request do
  it "is empty" do
    @requirements.find.to_a.should be_empty
    @docs.find.to_a.should be_empty
  end
  
  it "creates an empty index document in the database on first access" do
    visit "/"
    @docs.find.to_a.should have(1).items
    index = @docs.find_one
    index.should include("date", "_content", "_name")
    index["_name"].should == "index"
    index["_content"].should be_empty
    index["date"].should be_within(60).of(Time.now)
  end
  
  it "does not creates an empty index document if it already exists" do
    visit "/"
    visit "/"
    
    @docs.find.to_a.should have(1).items
  end
end

describe "An Openreqs application", :type => :request do
  it "redirects '' to '/'" do
    visit ""
    current_path.should == "/"
  end
  
  it "returns 'page not found' for unknown pages" do
    visit "/unknown"
    page.status_code.should == 404
  end
  
  it "returns 'page not found' for unknown documents" do
    visit "/d/unknown"
    page.status_code.should == 404
  end
  
  it "returns 'page not found' for unknown requirements" do
    visit "/r/unknown"
    page.status_code.should == 404
  end
end

describe "The index document", :type => :request do
  before(:all) do
    @doc_content = "This is the index content"
    @doc_new_content = "This is the index new content"
    @date =  Time.now.utc - 60
    doc = {"_name" => "index", "_content" => @doc_content, "date" => @date}
    @docs.save doc
  end
  
  it "redirects '/d/index' to '/'" do
    visit "/d/index"
    current_path.should == "/"
  end

  it "has a text view" do
    visit "/d/index.txt"
    page.response_headers["Content-Type"].should == "text/plain;charset=utf-8"
    body.should include(@doc_content)
  end
  
  it "has a json view"
  
  context "in the main view" do
    it "has a link to edit it" do
      visit "/"
      click_on "edit"
      current_path.should == "/d/index/edit"
    end
    
    it "has a link to see its history" do
      visit "/"
      click_on "history"
      current_path.should == "/d/index/history"
    end
    
    it "displays the document content" do
      visit "/"
      find("p").text.strip.should == @doc_content
    end
  end

  context "in the edit view" do
    it "displays the content in a form" do
      visit "/d/index/edit"
      find("form").text.strip.should == @doc_content
    end
    
    it "can save the document with the given content" do
      visit "/d/index/edit"
      fill_in "content", :with => @doc_new_content
      click_on "save"
      current_path.should == "/"
      find("p").text.strip.should == @doc_new_content
    end
  end

  context "in the history view" do
    it "has a link to go back to the document" do
      visit "/d/index/history"
      click_on "main_link"
      current_path.should == "/"
    end
    
    it "displays a list of revisions" do
      visit "/d/index/history"
      all("li").should have(2).items
    end
    
    it "has a link to the revisions" do
      visit "/d/index/history"
      find("li a.version").click
      current_path.should match(%r{^/d/index/.+})
    end
    
    it "has a link to the diff" do
      visit "/d/index/history"
      find("li a.diff").click
      current_path.should match(%r{^/d/index/.+/diff$})
    end
  end
  
  context "in the version view" do
    it "displays the document content of the first version" do
      visit "/d/index/#{@date.xmlschema}"
      find("p").text.strip.should == @doc_content
    end
    
    it "displays the document content of the second version" do
      visit "/d/index/#{(Time.now.utc + 60).xmlschema}"
      find("p").text.strip.should == @doc_new_content
    end
  end
  
end
