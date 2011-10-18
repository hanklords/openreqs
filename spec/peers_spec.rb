require "spec_helper"
require "rack/test"
require 'tempfile'


describe "An Openreqs application", :type => :request do
  include Rack::Test::Methods
  def app; Capybara.app end
  
  before(:all) do
    gen_key = OpenSSL::PKey::RSA.new(2048)
    @pem_file = Tempfile.new('pem')
    @pem_file.write gen_key.public_key.to_pem
  end
  
  before(:each) {@pem_file.rewind}
  after(:all) {@pem_file.close}
  
  it "advertises a unique public key" do
    visit "/a/key.pem"
    page.response_headers["Content-Type"].should == "application/x-pem-file"
    key = source
    key.should match(/^-----BEGIN RSA PUBLIC KEY-----$/)
    
    visit "/a/key.pem"
    source.should == key
  end
  
  it "can receive registration requests" do
    post "/a/peers/register", "user" => "me", "host" => "example.com",
      "key" => Rack::Test::UploadedFile.new(@pem_file.path, "application/x-pem-file")
    last_response.status.should == 200
    last_response.body.should be_empty
  end
  
  it "rejects registration requests without user" do
    post "/a/peers/register", "host" => "example.com",
      "key" => Rack::Test::UploadedFile.new(@pem_file.path, "application/x-pem-file")
    last_response.status.should == 400
  end
  
  it "rejects registration requests without host" do
    post "/a/peers/register", "user" => "me",
      "key" => Rack::Test::UploadedFile.new(@pem_file.path, "application/x-pem-file")
    last_response.status.should == 400
  end  
  
  it "rejects registration requests without key" do
    post "/a/peers/register", "host" => "example.com", "user" => "me"
    last_response.status.should == 400
  end
end
