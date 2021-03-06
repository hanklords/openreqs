require "spec_helper"

describe "An empty Openreqs application", :type => :request do
  it "is empty" do
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
  
  it "returns 'page not found' for unknown documents" do
    visit "/unknown"
    page.status_code.should == 404
    
    visit "/unknown.txt"
    page.status_code.should == 404
    
    visit "/unknown.json"
    page.status_code.should == 404
  end
  
  it "returns 'page not found' for unknown documents history" do
    visit "/unknown/history"
    page.status_code.should == 404
  end
    
  it "returns 'page not found' for unknown documents version" do
    visit "/unknown/#{Time.now.utc.xmlschema}"
    page.status_code.should == 404
    
    visit "/unknown/#{Time.now.utc.xmlschema}.txt"
    page.status_code.should == 404
    
    visit "/unknown/#{Time.now.utc.xmlschema}.json"
    page.status_code.should == 404
  end
      
  it "returns 'page not found' for unknown documents diff" do
    visit "/unknown/#{Time.now.utc.xmlschema}/diff"
    page.status_code.should == 404
  end
end

describe "The index document", :type => :request do
  before(:all) do
    @doc_name, @unknown_doc = "doc_name", "unknown_doc"
    @index_content, @doc_content = "This is the index content\n\n[[#@unknown_doc]]\n\n[[#@doc_name]]", "This is the doc content"
    @date =  Time.now.utc - 60
    @docs.save("_name" => "index", "_content" => @index_content, "date" => @date)
    @docs.save("_name" => @doc_name, "_content" => @doc_content, "date" => @date)
  end
  
  it "redirects '/index' to '/'" do
    visit "/index"
    current_path.should == "/"
  end
  
  it "has a link to edit it" do
    visit "/"
    click_on "edit"
    current_path.should == "/index/edit"
  end
  
  it "has a link to see its history" do
    visit "/"
    click_on "history"
    current_path.should == "/index/history"
  end
  
  it "displays the document content" do
    visit "/"
    find("p").text.strip.should == @index_content.lines.first.strip
  end

  it "links to the referenced documents" do
    visit "/"
    find_link(@doc_name).click
    current_path.should == "/#@doc_name"
  end
      
  it "links to the creation form for inexistant documents" do
    visit "/"
    find_link(@unknown_doc).click
    current_path.should == "/#@unknown_doc/edit"
  end
end

describe "A document", :type => :request do
  before(:all) do
    @date =  Time.now.utc - 60
    
    @req_name, @unknown_req_name = "req_name", "unknown_req_name"
    @req_content = "This the req content"
    @req_new_content = "This the req new content"

    @doc_name, @other_doc_name = "doc_name", "other_doc_name"
    @doc_text, @doc_new_text = "This is the doc content", "This is the doc new content"
    @doc_content = "#@doc_text\n\n[[#@other_doc_name]]\n{{#@unknown_req_name}}\n{{#@req_name}}"
    @doc_new_content = @doc_content.sub(@doc_text, @doc_new_text)
    @other_doc_content = "This the content of the other doc"
    
    @docs.save("_name" => @doc_name, "_content" => @doc_content, "date" => @date)
    @docs.save("_name" => @other_doc_name, "_content" => @other_doc_content, "date" => @date)
    @docs.save("_name" => @req_name, "_content" => @req_content, "date" => @date - 10)
    @docs.save("_name" => @req_name, "_content" => @req_new_content, "date" => @date + 30)
 end
 
 it "is listed in the json document list" do
   visit "/d.json"
   page.response_headers["Content-Type"].should == "application/json;charset=utf-8"
   json = JSON.load(source)
   json.should include(@doc_name, @other_doc_name)
 end
  
  it "has a text view (.txt)" do
    visit "/#@doc_name.txt"
    page.response_headers["Content-Type"].should == "text/plain;charset=utf-8"
    body.should include(@doc_text)
  end
  
  it "has a versioned text view (.txt)" do
    visit "/#@doc_name/#{(@date + 1).xmlschema}.txt"
    page.response_headers["Content-Type"].should == "text/plain;charset=utf-8"
    body.should include(@doc_text)
  end
  
  it "has a json view (.json)" do
    visit "/#@doc_name.json"
    page.response_headers["Content-Type"].should == "application/json;charset=utf-8"
    json = JSON.load(source)
    json.should include("_name" => @doc_name, "_content" => @doc_content)
    json["_reqs"].should have(1).items
  end
  
  it "has a versioned json view (.json)" do
    visit "/#@doc_name.json?with_history=1"
    page.response_headers["Content-Type"].should == "application/json;charset=utf-8"
    json = JSON.load(source)
    json.should have(1).items
    json[0].should include("_name" => @doc_name, "_content" => @doc_content)
  end

  context "in the main view" do
    it "links back to the summary" do
      visit "/#@doc_name"
      click_on "summary"
      current_path.should == "/"
    end
    
    it "links to the edit view" do
      visit "/#@doc_name"
      click_on "edit"
      current_path.should == "/#@doc_name/edit"
    end
    
    it "links to the history view" do
      visit "/#@doc_name"
      click_on "history"
      current_path.should == "/#@doc_name/history"
    end
    
    it "displays the document content" do
      visit "/#@doc_name"
      find("p").text.strip.should == @doc_text
    end
    
    it "links to the referenced documents" do
      visit "/#@doc_name"
      find_link(@other_doc_name).click
      current_path.should == "/#@other_doc_name"
    end
    
    it "displays the referenced requirements" do
      visit "/#@doc_name"
      find(".req p").text.strip.should == @req_new_content
    end
  end

  context "in the edit view" do
    it "displays the content in a form" do
      visit "/#@doc_name/edit"
      find("form textarea").text.strip.should == @doc_content
    end
    
    it "can save the document with the given content" do
      visit "/#@doc_name/edit"
      fill_in "_content", :with => @doc_new_content
      click_on "save"
      current_path.should == "/#@doc_name"
      find("p").text.strip.should == @doc_new_text
    end
  end

  context "in the history view" do
    it "has a link to go back to the document" do
      visit "/#@doc_name/history"
      click_on "main_link"
      current_path.should == "/#@doc_name"
    end
    
    it "displays a list of revisions" do
      visit "/#@doc_name/history"
      # 2 versions of the document + 1 version of the requirement
      all("li").should have(3).items
    end
    
    it "links to the revisions" do
      visit "/#@doc_name/history"
      find("li a.version").click
      current_path.should match(%r{^/#@doc_name/.+})
    end
    
    it "links to the diff" do
      visit "/#@doc_name/history"
      find("li a.diff").click
      current_path.should match(%r{^/#@doc_name/.+/diff$})
    end
  end
  
  context "in the version view" do
    it "displays the document content of the requested version" do
      # last version
      visit "/#@doc_name/history"
      find("li:first a.version").click
      find("p").text.strip.should == @doc_new_text
      find(".req p").text.strip.should == @req_new_content
      
      # first version
      visit "/#@doc_name/history"
      find("li:last a.version").click
      find("p").text.strip.should == @doc_text
      find(".req p").text.strip.should == @req_content
    end
    
    it "links back to the history view" do
      visit "/#@doc_name/history"
      find("li a.version").click
      find_link("history").click
      current_path.should == "/#@doc_name/history"
    end
  end
  
  context "in the diff view" do
    it "displays the text differencies with previous version" do
      visit "/#@doc_name/history"
      find("li:first a.diff").click
      find(".remove").text.should == @doc_text
      find(".add").text.should == @doc_new_text
    end
    
    it "displays the requirements text differencies with previous version" do
      visit "/#@doc_name/history"
      find("li:nth-child(2) a.diff").click
      find(".remove").text.should == @req_content
      find(".add").text.should == @req_new_content
    end
    
    it "displays the requirements attributes differencies with previous version"
    
    it "displays the added requirements from previous version" do
      visit "/#@doc_name/history"
      find("li:last a.diff").click
      find(".req .add").text.should == @req_content
    end
    
    it "displays the removed requirements from previous version"

    it "links back to the history view" do
      visit "/#@doc_name/history"
      find("li a.diff").click
      find_link("history").click
      current_path.should == "/#@doc_name/history"
    end
  end
  
end
