require 'net/http'

class Clone
  def self.uri_escape(uri)
    uri.gsub(/([^a-zA-Z0-9_.-]+)/) do
      '%' + $1.unpack('H2' * $1.bytesize).join('%').upcase
    end
  end
  
  def self.perform(url)
    db = Sinatra::Application.mongo
    db["docs"].remove
    db["requirements"].remove
    
    docs_list = Net::HTTP.get(URI.parse(url + "/d.json"))
    docs = JSON.load(docs_list)
    docs.each {|doc_name|
      doc = JSON.load(Net::HTTP.get(URI.parse(url + "/d/#{uri_escape(doc_name)}.json?with_history=1")))
      doc.each {|v| v["date"] = Time.parse(v["date"])}
      db["docs"].insert doc
    }
    
    reqs_list = Net::HTTP.get(URI.parse(url + "/r.json"))
    reqs = JSON.load(reqs_list)
    reqs.each {|req_name|
      req = JSON.load(Net::HTTP.get(URI.parse(url + "/r/#{uri_escape(req_name)}.json?with_history=1")))
      req.each {|v| v["date"] = Time.parse(v["date"])}
      db["requirements"].insert req
    }
  end
end

class Find
  def self.uri_escape(uri)
    uri.gsub(/([^a-zA-Z0-9_.-]+)/) do
      '%' + $1.unpack('H2' * $1.bytesize).join('%').upcase
    end
  end
  
  def self.perform(url)
    mongo = Sinatra::Application.mongo
    
    remote_text = Net::HTTP.get(URI.parse(url + "/a.json"))
    remote = JSON.load(remote_text)
    peer_request = {
      "date" => Time.now.utc, "server" => true,
      "_name" => remote["_name"], "local_url" => url,
      "key" => remote["key"]
    }
    mongo["peers.register"].insert peer_request
  end
end

class Sync
  def self.uri_escape(uri)
    uri.gsub(/([^a-zA-Z0-9_.-]+)/) do
      '%' + $1.unpack('H2' * $1.bytesize).join('%').upcase
    end
  end
  
  def self.perform(remote_name)
    mongo = Sinatra::Application.mongo
    
    remote = mongo["peers"].find_one("_name" => remote_name)
    doc_versions = remote["docs"] = {}
    
    docs_list = Net::HTTP.get(URI.parse(remote["local_url"] + "/d.json"))
    docs = JSON.load(docs_list)
    docs.each {|doc|
      version_list = Net::HTTP.get(URI.parse(remote["local_url"] + "/d/#{uri_escape(doc)}/history.json"))
      versions = JSON.load(version_list)
      doc_versions[doc] = versions.map {|v| Time.parse(v)}
    }
    
    mongo["peers"].save remote
  end
end
