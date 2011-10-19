require "spec_helper"
require "rack/test"
require 'tempfile'


describe "The peers registration manager", :type => :request do
  include Rack::Test::Methods
  def app; Capybara.app end
    
  before(:all) do
    gen_key = OpenSSL::PKey::RSA.new(128)
    @pem_file = Tempfile.new('pem')
    @pem_file.write gen_key.public_key.to_pem
    @name = "me@example.com"
  end
  
  before(:each) {@pem_file.rewind}
  after(:all) {@pem_file.close}
    
  it "rejects registration requests without user" do
    post "/a/peers/register",
      "key" => Rack::Test::UploadedFile.new(@pem_file.path, "application/x-pem-file")
    last_response.status.should == 400
  end
  
  it "rejects registration requests without key" do
    post "/a/peers/register", "user" => @name
    last_response.status.should == 400
  end
  
  it "receives registration requests" do
    post "/a/peers/register", "user" => @name,
      "key" => Rack::Test::UploadedFile.new(@pem_file.path, "application/x-pem-file")
    last_response.status.should == 200
    last_response.body.should == "OK"
  end
  
  it "displays registration requests" do
    visit "/a/peers"
    find("input[type='checkbox']").value.should == @name
  end
end

describe "The peers manager", :type => :request do
  before(:all) do
    @key = OpenSSL::PKey::RSA.new(128)
    @name = "me@example.com"
    
    peer_request = {"date" => Time.now.utc,
      "ip" => "127.0.0.1", "user_agent" => "User Agent",
      "_name" => @name,
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
    @data = "CONTENT"
    
    peer = {"_name" => @name, "key" => @key.public_key.to_pem}
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
