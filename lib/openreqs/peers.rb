require 'openssl'
require 'json'

class Peer
  def self.all(db)
    db["peers"].find("self" => {"$ne" => true})
  end
    
  def initialize(db, options)
    @db, @options = db, options
    @peer = @db["peers"].find_one("_name" => @options[:name])
  end
  
  def exist?; !@peer.nil? end
  def [](attr); exist? ? @peer[attr] : nil end
  def key; self["key"] end
  def name; self["_name"] end
    
  def to_json
    peer = @peer.clone
    peer.delete("_id")
    peer.delete("private_key")
    peer.delete("self")
    peer.to_json
  end
  
  def verify(sig, params)
    okey = OpenSSL::PKey::RSA.new(@peer["key"])
    sig = sig.unpack('m0')[0] rescue ""
    okey.verify(OpenSSL::Digest::SHA1.new, sig, sig_base_str(params))
  end

  def sig_base_str(params)
    params.map {|k,v| escape(k) + "=" + escape(v)}.sort.join("&")
  end
  
  def escape(text)
    text.to_s.gsub(/[^a-zA-Z0-9\-\.\_\~]/) do
      '%' + $&.unpack('H2' * $&.size).join('%').upcase
    end
  end  
end

class SelfPeer < Peer
  def initialize(db, options)
    @db, @options = db, options
    @peer = @db["peers"].find_one("self" => true)
    
    if !exist?
      name = @options[:host]
      gen_key = OpenSSL::PKey::RSA.new(2048)
      @peer = {"_name" => name, "private_key" => gen_key.to_pem, "key" => gen_key.public_key.to_pem, "self" => true}
      @db["peers"].insert @peer
    end
  end
  
  def sign(params)
    okey = OpenSSL::PKey::RSA.new(@peer["private_key"])
    [okey.sign(OpenSSL::Digest::SHA1.new, sig_base_str(params))].pack('m0').gsub(/\n$/,'')
  end
end
