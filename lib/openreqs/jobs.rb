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
    doc_versions = {}
    
    docs_list = Net::HTTP.get(URI.parse(remote["local_url"] + "/d.json"))
    docs = JSON.load(docs_list)
    mongo["docs.#{remote_name}"].remove
    mongo["requirements.#{remote_name}"].remove

    self_versions = {}
    mongo["docs"].find(
      {"_name" => {"$in" => docs}},
      {:fields => ["_name", "date"], :sort => ["date", :desc]}
    ).each {|doc|
      self_versions[doc["_name"]] ||= doc["date"]
    }
    
    docs.each {|doc_name|
      self_date = self_versions[doc_name]
      doc_url = remote["local_url"] + "/d/#{uri_escape(doc_name)}.json?with_history=1"
      doc_url << "&after=#{self_date.xmlschema(2)}" if self_date
      doc_json = Net::HTTP.get(URI.parse(doc_url))
      doc = JSON.load(doc_json)
      doc.each {|v| v["date"] = Time.parse(v["date"])}
      
      reqs_url = remote["local_url"] + "/d/#{uri_escape(doc_name)}/requirements.json?with_history=1"
      reqs_url << "&after=#{self_date.xmlschema(2)}" if self_date
      reqs_json = Net::HTTP.get(URI.parse(reqs_url))
      reqs = JSON.load(reqs_json).flatten
      reqs.each {|v| v["date"] = Time.parse(v["date"])}
      
      mongo["docs.#{remote_name}"].insert doc
      mongo["requirements.#{remote_name}"].insert reqs
    }
  end
end

class DocPull
  def self.uri_escape(uri)
    uri.gsub(/([^a-zA-Z0-9_.-]+)/) do
      '%' + $1.unpack('H2' * $1.bytesize).join('%').upcase
    end
  end
  
  def self.perform(remote_name, doc_name)
    mongo = Sinatra::Application.mongo
    
    last_local_doc = mongo["docs"].find_one({"_name" => doc_name}, {:fields => "date", :sort => ["date", :desc]})
    
    # Insert docs
    options = {}
    remote_doc_versions = DocVersions.new(mongo,
      :name => doc_name, :peer => remote_name,
      :after => last_local_doc && last_local_doc["date"])
    remote_doc_versions.each {|doc| mongo["docs"].insert doc.to_hash}
    
    last_remote_doc = remote_doc_versions.first.to_hash
    last_remote_doc.delete("_id")
    last_remote_doc["date"] = Time.now.utc
    mongo["docs"].insert last_remote_doc
    
    # Inserts Reqs
    remote_doc_versions.first.requirement_list.each {|req_name|
      remote_req_versions = ReqVersions.new(mongo,
        :name => req_name, :peer => remote_name,
        :after => last_local_doc && last_local_doc["date"])
      next if remote_req_versions.empty?
      
      remote_req_versions.each {|req| mongo["requirements"].insert req.to_hash}
      
      last_remote_req = remote_req_versions.first.to_hash
      last_remote_req.delete("_id")
      last_remote_req["date"] = Time.now.utc
      mongo["requirements"].insert last_remote_req
    }
  end
end
