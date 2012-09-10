require 'net/http'
require 'qu-mongo'
require 'qu-immediate'

JobsDatabase = Mongo::Connection.new
Qu.configure do |c|
  c.connection = Mongo::Connection.new.db("openreqs-qu")
end

class Clone
  def self.uri_escape(uri)
    uri.gsub(/([^a-zA-Z0-9_.-]+)/) do
      '%' + $1.unpack('H2' * $1.bytesize).join('%').upcase
    end
  end
  
  def self.perform(db_name, url)
    mongo = JobsDatabase.db(db_name)
    mongo["docs"].remove
    
    docs_list = Net::HTTP.get(URI.parse(url + "/d.json"))
    docs = JSON.load(docs_list)
    docs.each {|doc_name|
      doc = JSON.load(Net::HTTP.get(URI.parse(url + "/#{uri_escape(doc_name)}.json?with_history=1")))
      doc.each {|v| v["date"] = Time.parse(v["date"])}
      mongo["docs"].insert doc
    }
    
  end
end

class Find
  def self.uri_escape(uri)
    uri.gsub(/([^a-zA-Z0-9_.-]+)/) do
      '%' + $1.unpack('H2' * $1.bytesize).join('%').upcase
    end
  end
  
  def self.perform(db_name, url)
    mongo = JobsDatabase.db(db_name)
    
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
  
  def self.perform(db_name, remote_name)
    mongo = JobsDatabase.db(db_name)
    
    remote = mongo["peers"].find_one("_name" => remote_name)
    doc_versions = {}
    
    docs_list = Net::HTTP.get(URI.parse(remote["local_url"] + "/d.json"))
    docs = JSON.load(docs_list)
    mongo["docs.#{remote_name}"].remove

    self_versions = {}
    mongo["docs"].find(
      {"_name" => {"$in" => docs}},
      {:fields => ["_name", "date"], :sort => ["date", :desc]}
    ).each {|doc|
      self_versions[doc["_name"]] ||= doc["date"]
    }
    
    docs.each {|doc_name|
      self_date = self_versions[doc_name]
      doc_url = remote["local_url"] + "/#{uri_escape(doc_name)}.json?with_history=1"
#      doc_url << "&after=#{self_date.xmlschema(2)}" if self_date
      doc_json = Net::HTTP.get(URI.parse(doc_url))
      doc = JSON.load(doc_json)
      doc.each {|v| v["date"] = Time.parse(v["date"])}
      
      mongo["docs.#{remote_name}"].insert doc
    }
  end
end

class DocPull
  def self.uri_escape(uri)
    uri.gsub(/([^a-zA-Z0-9_.-]+)/) do
      '%' + $1.unpack('H2' * $1.bytesize).join('%').upcase
    end
  end
  
  def self.perform(db, name, remote_name, doc_name)
    mongo = JobsDatabase.db(db_name)
    
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
  end
end
