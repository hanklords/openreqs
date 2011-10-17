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
    
    visit "/d/unknown.txt"
    page.status_code.should == 404
    
    visit "/d/unknown.json"
    page.status_code.should == 404
  end
  
  it "returns 'page not found' for unknown documents history" do
    visit "/d/unknown/history"
    page.status_code.should == 404
  end
    
  it "returns 'page not found' for unknown documents version" do
    visit "/d/unknown/#{Time.now.utc.xmlschema}"
    page.status_code.should == 404
    
    visit "/d/unknown/#{Time.now.utc.xmlschema}.txt"
    page.status_code.should == 404
    
    visit "/d/unknown/#{Time.now.utc.xmlschema}.json"
    page.status_code.should == 404
  end
      
  it "returns 'page not found' for unknown documents diff" do
    visit "/d/unknown/#{Time.now.utc.xmlschema}/diff"
    page.status_code.should == 404
  end
  
  it "returns 'page not found' for unknown requirements" do
    visit "/r/unknown"
    page.status_code.should == 404
    
    visit "/r/unknown.txt"
    page.status_code.should == 404
    
    visit "/r/unknown.json"
    page.status_code.should == 404
  end
  
  it "returns 'page not found' for unknown requirements history" do
    visit "/r/unknown/history"
    page.status_code.should == 404
  end
  
  it "returns 'page not found' for unknown requirements version" do
    visit "/r/unknown/#{Time.now.utc.xmlschema}"
    page.status_code.should == 404
    
    visit "/r/unknown/#{Time.now.utc.xmlschema}.txt"
    page.status_code.should == 404
    
    visit "/r/unknown/#{Time.now.utc.xmlschema}.json"
    page.status_code.should == 404
  end
  
  it "returns 'page not found' for unknown requirements diff" do
    visit "/r/unknown/#{Time.now.utc.xmlschema}/diff"
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
    find("p").text.strip.should == @index_content.lines.first.strip
  end

  it "links to the referenced documents" do
    visit "/"
    find_link(@doc_name).click
    current_path.should == "/d/#@doc_name"
  end
      
  it "links to the creation form for inexistant documents" do
    visit "/"
    find_link(@unknown_doc).click
    current_path.should == "/d/#@unknown_doc/add"
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
    @doc_content = "#@doc_text\n\n[[#@other_doc_name]]\n[[#@unknown_req_name]]\n[[#@req_name]]"
    @doc_new_content = @doc_content.sub(@doc_text, @doc_new_text)
    @other_doc_content = "This the content of the other doc"
    
    @docs.save("_name" => @doc_name, "_content" => @doc_content, "date" => @date)
    @docs.save("_name" => @other_doc_name, "_content" => @other_doc_content, "date" => @date)
    @requirements.save("_name" => @req_name, "_content" => @req_content, "date" => @date - 10)
    @requirements.save("_name" => @req_name, "_content" => @req_new_content, "date" => @date + 30)
 end
  
  it "has a text view (.txt)" do
    visit "/d/#@doc_name.txt"
    page.response_headers["Content-Type"].should == "text/plain;charset=utf-8"
    body.should include(@doc_text)
  end
  
  it "has a versioned text view (.txt)" do
    visit "/d/#@doc_name/#{(@date + 1).xmlschema}.txt"
    page.response_headers["Content-Type"].should == "text/plain;charset=utf-8"
    body.should include(@doc_text)
  end
  
  it "has a json view (.json)"
  it "has a versioned json view (.json)"

  context "in the main view" do
    it "links back to the summary" do
      visit "/d/#@doc_name"
      click_on "summary"
      current_path.should == "/"
    end
    
    it "links to the edit view" do
      visit "/d/#@doc_name"
      click_on "edit"
      current_path.should == "/d/#@doc_name/edit"
    end
    
    it "links to the history view" do
      visit "/d/#@doc_name"
      click_on "history"
      current_path.should == "/d/#@doc_name/history"
    end
    
    it "displays the document content" do
      visit "/d/#@doc_name"
      find("p").text.strip.should == @doc_text
    end
    
    it "links to the referenced documents" do
      visit "/d/#@doc_name"
      find_link(@other_doc_name).click
      current_path.should == "/d/#@other_doc_name"
    end
    
    it "links to the creation form for inexistant requirements" do
      visit "/d/#@doc_name"
      find_link(@unknown_req_name).click
      current_path.should == "/r/#@unknown_req_name/add"
    end
    
    it "displays the referenced requirements" do
      visit "/d/#@doc_name"
      find(".req p").text.strip.should == @req_new_content
    end
        
    it "links to the edit view for existing requirements" do
      visit "/d/#@doc_name"
      find_link(@req_name).click
      current_path.should == "/r/#@req_name/edit"
    end
  end

  context "in the edit view" do
    it "displays the content in a form" do
      visit "/d/#@doc_name/edit"
      find("form textarea").text.strip.should == @doc_content
    end
    
    it "can save the document with the given content" do
      visit "/d/#@doc_name/edit"
      fill_in "content", :with => @doc_new_content
      click_on "save"
      current_path.should == "/d/#@doc_name"
      find("p").text.strip.should == @doc_new_text
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
      # 2 versions of the document + 1 version of the requirement
      all("li").should have(3).items
    end
    
    it "links to the revisions" do
      visit "/d/#@doc_name/history"
      find("li a.version").click
      current_path.should match(%r{^/d/#@doc_name/.+})
    end
    
    it "links to the diff" do
      visit "/d/#@doc_name/history"
      find("li a.diff").click
      current_path.should match(%r{^/d/#@doc_name/.+/diff$})
    end
  end
  
  context "in the version view" do
    it "displays the document content of the requested version" do
      # last version
      visit "/d/#@doc_name/history"
      find("li:first a.version").click
      find("p").text.strip.should == @doc_new_text
      find(".req p").text.strip.should == @req_new_content
      
      # first version
      visit "/d/#@doc_name/history"
      find("li:last a.version").click
      find("p").text.strip.should == @doc_text
      find(".req p").text.strip.should == @req_content
    end
    
    it "links back to the history view" do
      visit "/d/#@doc_name/history"
      find("li a.version").click
      find_link("history").click
      current_path.should == "/d/#@doc_name/history"
    end
  end
  
  context "in the diff view" do
    it "displays the text differencies with previous version" do
      visit "/d/#@doc_name/history"
      find("li:first a.diff").click
      find(".remove").text.should == @doc_text
      find(".add").text.should == @doc_new_text
    end
    
    it "displays the requirements text differencies with previous version" do
      visit "/d/#@doc_name/history"
      find("li:nth-child(2) a.diff").click
      find(".remove").text.should == @req_content
      find(".add").text.should == @req_new_content
    end
    
    it "displays the requirements attributes differencies with previous version"
    
    it "displays the added requirements from previous version" do
      visit "/d/#@doc_name/history"
      find("li:last a.diff").click
      find(".req .add").text.should == @req_content
    end
    
    it "displays the removed requirements from previous version"

    it "links back to the history view" do
      visit "/d/#@doc_name/history"
      find("li a.diff").click
      find_link("history").click
      current_path.should == "/d/#@doc_name/history"
    end
  end
  
end

describe "A requirement", :type => :request do
  before(:all) do
    @date =  Time.now.utc - 60
    
    @req_name = "req_name"
    @req_content = "This the req content"
    @req_new_content = "This the req new content"

    @doc_name = "doc_name"
    @doc_content = "This is the doc content\n\n[[#@req_name]]"
    
    @docs.save("_name" => @doc_name, "_content" => @doc_content, "date" => @date)
    @requirements.save("_name" => @req_name, "_content" => @req_content, "date" => @date)
  end
 
  it "has a text view (.txt)" do
    visit "/r/#@req_name.txt"
    page.response_headers["Content-Type"].should == "text/plain;charset=utf-8"
    body.should include(@req_content)
  end
   
  it "has a versioned text view (.txt)" do
    visit "/r/#@req_name/#{(@date + 1).xmlschema}.txt"
    page.response_headers["Content-Type"].should == "text/plain;charset=utf-8"
    body.should include(@req_content)
  end
  
  it "has a json view (.json)"
  it "has a versioned json view (.json)"

  context "in the main view" do
    it "links to the edit view" do
      visit "/r/#@req_name"
      click_on @req_name
      current_path.should == "/r/#@req_name/edit"
    end
    
    it "links to the history view"
    
    it "displays the document content" do
      visit "/r/#@req_name"
      find("p").text.strip.should == @req_content
    end
    
    it "links to the documents which reference it" do
      visit "/r/#@req_name"
      find("li", :text => /^ *origin/).find("a").text.should == @doc_name
    end
  end
    
  context "in the edit view" do
    it "displays the content in a form" do
      visit "/r/#@req_name/edit"
      find("form textarea").text.strip.should == @req_content
    end
    
    it "displays the attributes"
    
    it "can save the document with the given content" do
      visit "/r/#@req_name/edit"
      fill_in "content", :with => @req_new_content
      click_on "save"
      current_path.should == "/r/#@req_name"
      find("p").text.strip.should == @req_new_content
    end
  end
  
  context "in the history view" do
    it "has a link to go back to the requirement" do
      visit "/r/#@req_name/history"
      click_on "main_link"
      current_path.should == "/r/#@req_name"
    end
    
    it "displays a list of revisions" do
      visit "/r/#@req_name/history"
      all("li").should have(2).items
    end
    
    it "links to the revisions" do
      visit "/r/#@req_name/history"
      find("li a.version").click
      current_path.should match(%r{^/r/#@req_name/.+})
    end
    
    it "links to the diff" do
      visit "/r/#@req_name/history"
      find("li a.diff").click
      current_path.should match(%r{^/r/#@req_name/.+/diff$})
    end
  end
    
  context "in the version view" do
    it "displays the requirement content of the requested version" do
      visit "/r/#@req_name/history"
      find("li a.version").click
      find("p").text.strip.should == @req_new_content
    end
    
    it "links back to the history view"
  end
  
  context "in the diff view" do
    it "displays the text differencies with previous version" do
      visit "/r/#@req_name/history"
      find("li a.diff").click
      find(".remove").text.should == @req_content
      find(".add").text.should == @req_new_content
    end
    
    it "displays the requirements attributes differencies with previous version"

    it "links back to the history view" do
      visit "/r/#@req_name/history"
      find("li a.diff").click
      find_link("history").click
      current_path.should == "/r/#@req_name/history"
    end
  end
  
end
