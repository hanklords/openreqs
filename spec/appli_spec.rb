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
    @index_content = "This is the index content"
    @date =  Time.now.utc - 60
    index = {"_name" => "index", "_content" => @index_content, "date" => @date}
    @docs.save index
  end
  
  it "redirects '/d/index' to '/'" do
    visit "/d/index"
    current_path.should == "/"
  end
  
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
    find("p").text.strip.should == @index_content
  end
  
  it "links to the creation form for inexistant documents" do
    @unknown_doc = "unknown"
    index = @docs.find_one
    index["_content"] << "\n[[#@unknown_doc]]"
    @docs.save index
    
    visit "/"
    find("p a").click
    current_path.should == "/d/#@unknown_doc/add"
  end
end

describe "A document", :type => :request do
  before(:all) do
    @req_name, @unknown_req_name = "req_name", "unknown_req_name"
    @doc_name, @other_doc_name = "doc_name", "other_doc_name"
    @doc_content = "This is the doc content"
    @doc_new_content = "This is the doc new content"
    @other_doc_content = @doc_content + "\n[[#@doc_name]]" + "\n[[#@unknown_req_name]]"
    @date =  Time.now.utc - 60
    
    @docs.save("_name" => @doc_name, "_content" => @doc_content, "date" => @date)
    @docs.save("_name" => @other_doc_name, "_content" => @other_doc_content, "date" => @date)
  end
  
  it "has a text view (.txt)" do
    visit "/d/#@doc_name.txt"
    page.response_headers["Content-Type"].should == "text/plain;charset=utf-8"
    body.should include(@doc_content)
  end
  
  it "has a json view (.json)"
  
  context "in the main view" do
    it "has a link to return to the summary" do
      visit "/d/#@doc_name"
      click_on "summary"
      current_path.should == "/"
    end
    
    it "has a link to edit it" do
      visit "/d/#@doc_name"
      click_on "edit"
      current_path.should == "/d/#@doc_name/edit"
    end
    
    it "has a link to see its history" do
      visit "/d/#@doc_name"
      click_on "history"
      current_path.should == "/d/#@doc_name/history"
    end
    
    it "displays the document content" do
      visit "/d/#@doc_name"
      find("p").text.strip.should == @doc_content
    end
    
    it "links to the referenced documents" do
      visit "/d/#@other_doc_name"
      find_link(@doc_name).click
      current_path.should == "/d/#@doc_name"
    end
    
    it "links to the creation form for inexistant requirements"
    it "displays the referenced requirements"
  end

  context "in the edit view" do
    it "displays the content in a form" do
      visit "/d/#@doc_name/edit"
      find("form").text.strip.should == @doc_content
    end
    
    it "can save the document with the given content" do
      visit "/d/#@doc_name/edit"
      fill_in "content", :with => @doc_new_content
      click_on "save"
      current_path.should == "/d/#@doc_name"
      find("p").text.strip.should == @doc_new_content
    end
  end

  context "in the history view" do
    it "has a link to go back to the document" do
      visit "/d/#@doc_name/history"
      click_on "main_link"
      current_path.should == "/d/#@doc_name"
    end
    
    it "displays a list of revisions" do
      visit "/d/#@doc_name/history"
      all("li").should have(2).items
    end
    
    it "has a link to the revisions" do
      visit "/d/#@doc_name/history"
      find("li a.version").click
      current_path.should match(%r{^/d/#@doc_name/.+})
    end
    
    it "has a link to the diff" do
      visit "/d/#@doc_name/history"
      find("li a.diff").click
      current_path.should match(%r{^/d/#@doc_name/.+/diff$})
    end
  end
  
  context "in the version view" do
    it "displays the document content of the requested version" do
      visit "/d/#@doc_name/#{(Time.now.utc + 60).xmlschema}"
      find("p").text.strip.should == @doc_new_content
    end
  end
end