DB = Mongo::Connection.new.db("openreqs-test")

class Clone
  def self.perform(url)
    r = Net::HTTP.get(URI.parse(url + "/d.json"))
    docs = JSON.load(r)
    docs.each {|doc_name|
      doc = JSON.load(Net::HTTP.get(URI.parse(url + "/d/#{doc_name}.json?with_history=1")))
      doc.each {|v| v["date"] = Time.parse(v["date"])}
      DB["docs"].insert doc
    }
    
  end
end
