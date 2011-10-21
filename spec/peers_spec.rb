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
  
describe "The peers authentication verifier" do
  include Rack::Test::Methods
  def app; Capybara.app end
  
  before(:all) do
    @key = OpenSSL::PKey::RSA.new(2048)
    @name = "me@example.com"
    @local_url = "http://localhost:9999/application"
    @session = OpenSSL::Random.random_bytes(16).unpack("H*")[0]

    peer = {"_name" => @name, "key" => @key.public_key.to_pem, "local_url" => @local_url}
    @db["peers"].save peer
  end
  
  it "rejects unknown peers" do
    post "/a/peers/unknown/authentication", :session => @session, :name => "unknown", :signature => "BAD_SIGNATURE"

    last_response.status.should == 404
    last_response.body.should match(/^KO/)
  end
  
  it "rejects unknown sessions"
  
  it "rejects not signed requests" do
    post "/a/peers/#@name/authentication", :session => @session, :name => @name

    last_response.status.should == 400
    last_response.body.should match(/^KO/)
  end
    
  it "rejects bad signatures" do
    post "/a/peers/#@name/authentication", :session => @session, :name => @name, :signature => "BAD_SIGNATURE"

    last_response.status.should == 400
    last_response.body.should match(/^KO/)
  end
    
  it "verifies signatures of messages" do
    auth_params = {:session => @session, :name => @name}
    sig_base_str = auth_params.map {|k,v| URI.escape(k.to_s) + "=" + URI.escape(v.to_s)}.sort.join("&")
    auth_params["signature"] = [@key.sign(OpenSSL::Digest::SHA1.new, sig_base_str)].pack('m0').gsub(/\n$/,'')

    post "/a/peers/#@name/authentication", auth_params
    
    last_response.status.should == 200
    last_response.body.should == "OK"
  end
end

describe "The peers authenticater", :type => :request do
  before(:all) do
    @key = OpenSSL::PKey::RSA.new(2048)
    @name = "me@example.com"
    @local_url = "http://localhost:9999/application"
    @data = "CONTENT"
    
    peer = {"_name" => @name, "key" => @key.public_key.to_pem, "local_url" => @local_url}
    self_peer = {"_name" => @name, "private_key" => @key.to_pem, "key" => @key.public_key.to_pem, "self" => true}
    @db["peers"].save peer
    @db["peers"].save self_peer
  end  
  
  it "authenticate users" do
    session = OpenSSL::Random.random_bytes(16).unpack("H*")[0]
    args = {"name" => @name, "peer" => @name, "session" => session, "return_to" => "/a/peers/#@name/authentication"}
    visit "/a/peers/authenticate?#{URI.encode_www_form(args)}"
    click_on "save"
    
    source.should == "OK"
  end
end
