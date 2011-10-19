require "spec_helper"
require "rack/test"
require 'tempfile'


describe "The peers registration manager" do
  include Rack::Test::Methods
  def app; Capybara.app end
    
  before(:all) do
    gen_key = OpenSSL::PKey::RSA.new(128)
    @pem_file = Tempfile.new('pem')
    @pem_file.write gen_key.public_key.to_pem
    @name = "me@example.com"
    @local_url = "http://localhost:9999/application"
  end
  
  before(:each) {@pem_file.rewind}
  after(:all) {@pem_file.close}
  
  it "rejects registration requests without key" do
    post "/a/peers/#@name/register", "local_url" => @local_url
    last_response.status.should == 400
    last_response.body.should match(/^KO/)
  end
    
  it "rejects registration requests without local url" do
    post "/a/peers/#@name/register",
      "key" => Rack::Test::UploadedFile.new(@pem_file.path, "application/x-pem-file")
    last_response.status.should == 400
    last_response.body.should match(/^KO/)
  end
  
  it "receives registration requests" do
    post "/a/peers/#@name/register",
      "local_url" => @local_url,
      "key" => Rack::Test::UploadedFile.new(@pem_file.path, "application/x-pem-file")
    last_response.status.should == 200
    last_response.body.should == "OK"
    
    # Check database
    @pem_file.rewind
    peer_request = @db["peers.register"].find_one
    peer_request.should be
    peer_request.delete "_id"
    peer_request.delete "date"
    peer_request.should == {
      "_name" => @name, "user_agent" => nil,
      "local_url" => @local_url, "key" => @pem_file.read, "ip" => "127.0.0.1"
    }
  end
end

describe "The peers manager", :type => :request do
  before(:all) do
    @key = OpenSSL::PKey::RSA.new(128)
    @name = "me@example.com"
    @local_url = "http://localhost:9999/application"
    
    peer_request = {"date" => Time.now.utc,
      "ip" => "127.0.0.1", "user_agent" => "User Agent",
      "_name" => @name, "local_url" => @local_url,
      "key" => @key.public_key.to_pem
    }
    @db["peers.register"].save peer_request
  end
  
  it "advertises a unique public key" do
    visit "/a/key.pem"
    page.response_headers["Content-Type"].should == "application/x-pem-file"
    key = source
    key.should match(/^-----BEGIN RSA PUBLIC KEY-----$/)
    
    visit "/a/key.pem"
    source.should == key
  end

  it "displays registration requests" do
    visit "/a/peers"
    find("input[type='checkbox']").value.should == @name
  end
  
  it "accepts registrations" do
    visit "/a/peers"
    check("users[]")
    click_on "save"
     
    current_path.should == "/a/peers"
    all("input[type='checkbox']").should be_empty
  end
  
  it "displays peers" do
    visit "/a/peers"
    find("li").text.strip.should == @name
  end
   
  it "provides peer keys" do
    visit "/a/peers/#@name.pem"
    page.response_headers["Content-Type"].should == "application/x-pem-file"
    source.should match(/^-----BEGIN RSA PUBLIC KEY-----$/)
  end
end
  
describe "The peers manager signature verifier" do
  include Rack::Test::Methods
  def app; Capybara.app end
  
  before(:all) do
    @key = OpenSSL::PKey::RSA.new(2048)
    @name = "me@example.com"
    @local_url = "http://localhost:9999/application"
    @data = "CONTENT"
    
    peer = {"_name" => @name, "key" => @key.public_key.to_pem, "local_url" => @local_url}
    @db["peers"].save peer
  end
  
  it "rejects unknown peers" do
    header "content-type", "text/plain"
    header "x-or-signature", "BAD_SIGNATURE"
    post "/a/peers/unknown/verify", @data

    last_response.status.should == 404
    last_response.body.should match(/^KO/)
  end
  
  it "rejects not signed requests" do
    header "content-type", "text/plain"
    post "/a/peers/#@name/verify", @data

    last_response.status.should == 400
    last_response.body.should match(/^KO/)
  end
    
  it "rejects bad signatures" do
    header "content-type", "text/plain"
    header "x-or-signature", "BAD_SIGNATURE"
    post "/a/peers/#@name/verify", @data

    last_response.status.should == 400
    last_response.body.should match(/^KO/)
  end
    
  it "verifies signatures of messages" do
    sig = [@key.sign(OpenSSL::Digest::SHA1.new, @data)].pack('m0').gsub(/\n$/,'')

    header "content-type", "text/plain"
    header "x-or-signature", sig
    post "/a/peers/#@name/verify", @data
  end
end
