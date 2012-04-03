lib = File.expand_path('../lib', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'sinatra'
require 'haml'
require 'mongo'
require 'time'
require 'qu-mongo'
require 'qu-immediate'
require 'stringio'
require 'zlib'
require 'openreqs/jobs'
require 'openreqs/peers'
require 'openreqs/content'
require 'openreqs/diff'

configure do
  set :mongo, Mongo::Connection.new.db("openreqs")
  mime_type :pem, "application/x-pem-file"
  
  Qu.configure do |c|
    c.connection = Mongo::Connection.new.db(settings.mongo.name + "-qu")
  end
end

helpers do
  def mongo; settings.mongo end
end

set :views, Proc.new { File.join(root, "views", "default") }
before {content_type :html, :charset => 'utf-8'}

get '/a/key.pem' do
  self_peer = SelfPeer.new(mongo, :host => request.host)
  
  content_type :pem
  self_peer.key
end

get '/a.json' do
  self_peer = SelfPeer.new(mongo, :host => request.host)
  
  content_type :json
  self_peer.to_json
end

get '/a/peers' do
  @peers = Peer.all(mongo)
  @requests = mongo["peers.register"].find
  
  haml :peers
end

post '/a/peers/add' do
  Qu.enqueue Find, params[:server]
  
  redirect to("/a/peers")
end

post '/a/peers' do
  users  = params[:users] || []
  peer_requests = mongo["peers.register"].find("_name" => {"$in" => users})

  peer_requests.each {|peer_request|
    peer = {
      "_name" => peer_request["_name"],
      "key"   => peer_request["key"],
      "local_url" => peer_request["local_url"]
    }
    
    mongo["peers.register"].remove("_id" => peer_request["_id"])
    mongo["peers"].insert peer
  }
  redirect to("/a/peers")
end

post '/a/peers/:name/register' do
  content_type :txt
  name, local_url, key = params[:name], params[:local_url], params[:key]
  error 400, "KO No Local URL" if local_url.nil?
  if key.nil? || !key.is_a?(Hash) || key[:tempfile].nil?
    error 400, "KO No key"
  end
  if Peer.new(mongo, :name => params[:name]).exist?
    error 500, "KO Peer already registered"
  end

  peer_request = {"date" => Time.now.utc,
    "ip" => request.ip, "user_agent" => request.user_agent,
    "_name" => name, "local_url" => local_url,
    "key" => key[:tempfile].read
  }
  mongo["peers.register"].insert peer_request
  "OK"
end

post '/a/peers/:name/authentication' do
  content_type :txt
  peer = Peer.new(mongo, :name => params[:name])
  error 404, "KO peer #{params[:name]} unknown" if !peer.exist?
  
  sig = params.delete("signature")
  if peer.verify(sig, params)
    "OK"
  else
    error 400, "KO Bad Signature"
  end
end

get '/a/peers/authenticate' do
  @name, @peer, @session, @return_to = params[:name], params[:peer], params[:session], params[:return_to]

  self_peer = SelfPeer.new(mongo, :host => request.host)
  
  @return_params = {:name => @name, :session => @session}
  @return_params["signature"] = self_peer.sign(@return_params)
  
  haml :peers_authenticate
end

get '/a/peers/:name.pem' do
  peer = Peer.new(mongo, :name => params[:name])
  not_found if !peer.exist?

  content_type :pem
  peer.key
end

get '/a/peers/:name' do
  @name = params[:name]
  @peer = Peer.new(mongo, :name => @name)
  not_found if !@peer.exist?

  @docs = mongo["docs.#@name"].find({}, {:fields => "_name"}).map {|doc| doc["_name"]}.uniq
  haml :peer
end

get '/a/peers/:peer/d/:doc' do
  @peer = Peer.new(mongo, :name => params[:peer])
  not_found if !@peer.exist?
  
  @doc = Doc.new(mongo, params[:doc], :peer => params[:peer], :context => self)
  not_found if !@doc.exist?
  @name = @doc.name
  
  haml :doc
end

get '/a/peers/:peer/d/:doc/diff' do
  @peer = Peer.new(mongo, :name => params[:peer])
  not_found if !@peer.exist?
  
  @doc_a = Doc.new(mongo, params[:doc], :peer => params[:peer], :context => self)
  not_found if !@doc_a.exist?
  
  @doc_b = Doc.new(mongo, params[:doc], :context => self)

  @name = params[:doc]
  @diff = DocDiff.new(@doc_b, @doc_a, :context => self)
  
  haml :doc_diff
end

post '/a/peers/:peer/d/:doc/pull' do
  @peer = Peer.new(mongo, :name => params[:peer])
  not_found if !@peer.exist?
  
  @doc = Doc.new(mongo, params[:doc], :peer => params[:peer], :context => self)
  not_found if !@doc.exist?
  
  Qu.enqueue DocPull, @peer.name, @doc.name
  redirect to("/a/peers/#{@peer.name}")
end

post '/a/peers/:name/sync' do
  Qu.enqueue Sync, params[:name]
  
  redirect to("/a/peers/#{params[:name]}")  
end

get '/a/clone' do
    haml %q{
%div
  Enter the Openreqs server address:
  %form(method="post")
    %input(type="text" name="url")
    %input#clone(type="submit" value="Clone")
}
end

post '/a/clone' do
  Qu.enqueue Clone, params[:url]
  ""
end

get '/a/import' do
    haml %q{
%div
  Choose a file to import
  %form(method="post" enctype="multipart/form-data")
    %input(type="file" name="import")
    %br
    %input#import(type="submit" value="Import")
}  
end

post '/a/import' do
  import_doc = params[:import]
  not_found if import_doc.nil?

  begin
    gz = Zlib::GzipReader.new(import_doc[:tempfile])
    import_json = JSON.load(gz.read)
    gz.close
    
    import_peer = import_json["peers"].first
    if not Peer.new(mongo, :name => import_peer["_name"]).exist?
      mongo["peers"].insert import_peer
    end
    
    import_json["docs"].each { |doc| doc["date"] = Time.parse(doc["date"]) }
    import_json["reqs"].flatten.each { |req| req["date"] = Time.parse(req["date"]) }
    
    mongo["docs.#{import_peer["_name"]}"].insert import_json["docs"]
    mongo["requirements.#{import_peer["_name"]}"].insert import_json["reqs"].flatten
    
    redirect to("/a/peers/#{import_peer["_name"]}")
  rescue Zlib::GzipFile::Error , JSON::ParserError
    "Bad file"
  end
end

get '' do
  redirect to('/')
end

get '/d/index' do
  redirect to('/')
end

get '/' do
  @doc = DocIndex.new(mongo, :context => self)
  @name = @doc.name
  
  p mongo["docs"].find.to_a
  haml :index
end

get '/d.json' do
  content_type :json
  mongo["docs"].find({}, {:fields => "_name"}).map {|d| d["_name"]}.uniq.to_json
end

get '/d' do
  @docs = mongo["docs"].find({}, {:fields => "_name"}).map {|d| d["_name"]}.uniq
  
  haml %q{
%ul
  - @docs.each do |doc|
    %li
      %a{:href => to("/d/#{doc}")}= doc
      %form{:method => "post", :action => to("/d/#{doc}/delete")}
        %input.delete(type="submit" value="Supprimer")
}
end

get '/d/:doc.txt' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?

  content_type :txt
  @doc.to_txt
end

get '/d/:doc.reqif' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?

  content_type :txt
  @doc.to_reqif
end

get '/d/:doc.json' do
  if params[:with_history] == "1"
    after = Time.xmlschema(params[:after]) rescue nil
    @doc = DocVersions.new(mongo, :name => params[:doc], :after => after)
  else
    @doc = Doc.new(mongo, params[:doc], :context => self)
  end
  not_found if !@doc.exist?
  
  content_type :json
  @doc.to_json
end

get '/d/:doc.or.gz' do
  @doc = DocVersions.new(mongo, :name => params[:doc])
  not_found if !@doc.exist?
  
  @reqs = @doc.map{|doc_version|
    doc_version.requirement_list.map {|req_name|
      ReqVersions.new(mongo, :name => req_name, :context => self)
    }
  }.flatten.uniq
  self_peer = SelfPeer.new(mongo, :host => request.host)

  
  content_type 'application/x-openreqs'
  or_gz = Zlib::GzipWriter.new(StringIO.new)
  or_gz.orig_name = params[:doc] + ".json"
  or_gz << {"peers" => [self_peer], "docs" => @doc, "reqs" => @reqs}.to_json
  or_gz.finish.string
end

get '/d/:doc' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  @name = @doc.name
  
  haml :doc
end

get '/d/:doc/files/:file' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  
  @fs = Mongo::GridFileSystem.new(mongo)
  begin
    file = @fs.open("/d/" + params[:doc] + "/" + params[:file], "r")
    content_type file.content_type
    file
  rescue Mongo::GridFileNotFound
    not_found
  end
end

get '/d/:doc/files/' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  
  haml %q{
%div
  Choose a file to attach
  %form(method="post" enctype="multipart/form-data")
    %input(type="file" name="file")
    %br
    %input#upload(type="submit" value="Upload")
}  
end

post '/d/:doc/files/' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  
  upload_file = params[:file]
  not_found if upload_file.nil?

  @fs = Mongo::GridFileSystem.new(mongo)
  file = @fs.open("/d/" + params[:doc] + "/" + upload_file[:filename], "w") do |f|
    f.write upload_file[:tempfile].read
  end
  
  redirect to('/d/' + URI.escape(params[:doc]))
end

get '/d/:doc/requirements.json' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  if params[:with_history] == "1"
    after = Time.xmlschema(params[:after]) rescue nil
    @reqs = @doc.requirement_list.map {|req_name|
      ReqVersions.new(mongo, :name => req_name, :after => after, :context => self)
    }
  else
    @reqs = @doc.requirement_list.map {|req_name| Req.new(mongo, req_name, :context => self) }
  end

  content_type :json
  @reqs.to_json
end

post '/d/:doc/delete' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
 
  mongo["docs"].remove "_name" => @doc.name
  redirect to('/d')
end

get '/d/:doc/edit' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  @name = @doc.name
  @content = @doc.content
  
  cache_control :no_cache
  haml :doc_edit
end

post '/d/:doc/edit' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  doc_data = @doc.to_hash
  doc_data.delete "_id"
  doc_data["_name"] = params[:doc]
  doc_data["date"] = Time.now.utc
  doc_data["_content"] = params[:content]
  mongo["docs"].save doc_data

  redirect to('/d/' + URI.escape(params[:doc]))
end

get '/d/:doc/history.json' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?

  @dates = mongo["docs"].find({"_name" => params[:doc]}, {:fields => "date", :sort => ["date", :asc]}).map {|doc| doc["date"]}
  req_names = CreolaExtractURL.new(@doc["_content"]).to_a
  @dates.concat mongo["requirements"].find({
    "_name" => {"$in" => req_names},
    "date"=> {"$gt" => @dates[0]}
   }, {:fields => "date"}).map {|req| req["date"]}
  @dates = @dates.sort.reverse
  
  content_type :json
  @dates.map {|d| d.xmlschema(2)}.to_json
end

get '/d/:doc/history.rss' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?

  @name = params[:doc]
  @dates = mongo["docs"].find({"_name" => params[:doc]}, {:fields => "date", :sort => ["date", :asc]}).map {|doc| doc["date"]}
  req_names = CreolaExtractURL.new(@doc["_content"]).to_a
  @dates.concat mongo["requirements"].find({
    "_name" => {"$in" => req_names},
    "date"=> {"$gt" => @dates[0]}
   }, {:fields => "date"}).map {|req| req["date"]}
  
  @dates = @dates.sort.reverse
  @date = @dates[0]
  @docs = @dates.map {|date| Doc.new(mongo, params[:doc], :date => date, :context => self)}
  @doc_diffs = @docs.each_cons(2).map {|doc_a, doc_b| DocDiff.new(doc_b, doc_a, :context => self) }
  
  content_type :rss
  haml :doc_history_rss
end

get '/d/:doc/history' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?

  @dates = mongo["docs"].find({"_name" => params[:doc]}, {:fields => "date", :sort => ["date", :asc]}).map {|doc| doc["date"]}
  req_names = CreolaExtractURL.new(@doc["_content"]).to_a
  @dates.concat mongo["requirements"].find({
    "_name" => {"$in" => req_names},
    "date"=> {"$gt" => @dates[0]}
   }, {:fields => "date"}).map {|req| req["date"]}
  @dates = @dates.sort.reverse
  @name = params[:doc]
  
  haml :doc_history
end

get '/d/:doc/:date.txt' do
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @doc = Doc.new(mongo, params[:doc], :date => @date, :context => self)
  not_found if !@doc.exist?
  
  content_type :txt
  @doc.to_txt
end

get '/d/:doc/:date.json' do
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @doc = Doc.new(mongo, params[:doc], :date => @date, :context => self)
  not_found if !@doc.exist?
  
  content_type :json
  @doc.to_json
end

get '/d/:doc/:date' do
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @doc = Doc.new(mongo, params[:doc], :date => @date, :context => self)
  not_found if !@doc.exist?
  
  @name = params[:doc]
  haml :doc_version
end

get '/d/:doc/:date/diff' do
  @date = @date_a = Time.xmlschema(params[:date]) + 1 rescue not_found
  @doc_a = Doc.new(mongo, params[:doc], :date => @date_a, :context => self)
  not_found if !@doc_a.exist?
  
  @date_param = Time.xmlschema(params[:compare]) + 1 rescue nil
  @date_b = @date_param || (@date_a - 1)
  @doc_b = Doc.new(mongo, params[:doc], :date => @date_b, :context => self)

  @name = params[:doc]
  @diff = DocDiff.new(@doc_b, @doc_a, :context => self)
  
  haml :doc_diff
end

get '/r.json' do
  content_type :json
  mongo["requirements"].find({}, {:fields => "_name"}).map {|d| d["_name"]}.uniq.to_json
end

get '/r/:req.json' do
  if params[:with_history] == "1"
    after = Time.xmlschema(params[:after]) rescue nil
    @req = ReqVersions.new(mongo, :name => params[:req], :after => after, :context => self)
  else
    @req = Req.new(mongo, params[:req], :context => self)
  end
  not_found if !@req.exist?

  content_type :json
  @req.to_json
end

get '/r/:req.txt' do
  @req = Req.new(mongo, params[:req], :context => self)
  not_found if !@req.exist?

  content_type :txt
  @req.to_txt
end

get '/r/:req' do
  @req = Req.new(mongo, params[:req], :context => self)
  not_found if !@req.exist?

  latest_doc = {}
  mongo["docs"].find({}, {:fields => ["_name", "date"], :sort => ["date", :desc]}).each {|doc|
    latest_doc[doc["_name"]] ||= doc
  }
  latest = latest_doc.map {|k,v| v["_id"]}
  
  @origin = []
  mongo["docs"].find({"_id" => {"$in" => latest}}, {:fields => ["_name", "_content"]}).each {|doc|
    if CreolaExtractURL.new(doc["_content"]).to_a.include? params[:req]
      @origin << doc["_name"]
    end
  }
  
  ReqHTML.new(@req, :context => self).to_html
end

get '/r/:req/edit' do
  @req = Req.new(mongo, params[:req], :context => self)

  cache_control :no_cache
  haml :doc_req_edit
end

get '/r/:req/history.json' do
  @req = Req.new(mongo, params[:req], :context => self)
  not_found if !@req.exist?
  
  @dates = mongo["requirements"].find({"_name" => params[:req]}, {:fields => "date", :sort => ["date", :desc]}).map {|req| req["date"]}

  content_type :json
  @dates.map {|d| d.xmlschema(2)}.to_json
end

get '/r/:req/history' do
  @req = Req.new(mongo, params[:req], :context => self)
  not_found if !@req.exist?
  
  @dates = mongo["requirements"].find({"_name" => params[:req]}, {:fields => "date", :sort => ["date", :desc]}).map {|req| req["date"]}
  @name = params[:req]
  
  haml :req_history
end

get '/r/:req/:date.json' do
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @req = Req.new(mongo, params[:req], :date => @date, :context => self)
  not_found if !@req.exist?

  content_type :json
  @req.to_json
end

get '/r/:req/:date.txt' do
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @req = Req.new(mongo, params[:req], :date => @date, :context => self)
  not_found if !@req.exist?
  
  content_type :txt
  @req.to_txt
end

get '/r/:req/:date' do
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @req = Req.new(mongo, params[:req], :date => @date, :context => self)
  not_found if !@req.exist?
  
  ReqHTML.new(@req, :context => self).to_html
end

get '/r/:req/:date/diff' do
  @date = @date_a = Time.xmlschema(params[:date]) + 1 rescue not_found
  @doc_a = Req.new(mongo, params[:req], :date => @date_a, :context => self)
  not_found if !@doc_a.exist?
  
  @date_param = Time.xmlschema(params[:compare]) + 1 rescue nil
  @date_b = @date_param || (@date_a - 1)
  @doc_b = Req.new(mongo, params[:req], :date => @date_b, :context => self)

  @name = params[:req]
  @diff = ReqDiff.new(@doc_b, @doc_a, :context => self)
  
  haml :req_diff
end

post '/r/:req/edit' do
  @req = Req.new(mongo, params[:req], :context => self)
  req_data = @req.to_hash
  req_data.delete "_id"
  req_data["_name"] = params[:req]
  req_data["date"] = Time.now.utc
  req_data["_content"] = params[:content]
  @req.attributes.each {|k,v|
  	puts k
  	puts "v#{k}"
  	if !params[k].empty?
    		if !params["v#{k}"].empty?
      			req_data[params[k]] = params["v#{k}"]
    		else
      			req_data.delete params[k]
   		end
  	end}
  if !params[:key].empty?
    if !params[:value].empty?
      req_data[params[:key]] = params[:value]
    else
      req_data.delete params[:key]
    end
  end
  
  mongo["requirements"].save req_data
  
  redirect to('/r/' + URI.escape(params[:req]))
end
