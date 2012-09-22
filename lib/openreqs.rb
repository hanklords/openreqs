require 'sinatra/base'
require 'haml'
require 'mongo'
require 'time'
require 'stringio'
require 'zlib'
require 'openreqs/jobs'
require 'openreqs/peers'
require 'openreqs/content'
require 'openreqs/diff'

class Openreqs < Sinatra::Base
configure do
  set :root, File.expand_path("../..", __FILE__)
  set :views, File.join(root, "views", "default")
  set :doc_template, %q{= @inline.content.to_html}
  set :req_inline_template, lambda {File.read(File.join(views, 'req_inline.haml'))}
  
  mime_type :pem, "application/x-pem-file"
end

helpers do
  attr_writer :db_name, :mongo_connection
  
  def db_name; @db_name || "openreqs" end
  def mongo_connection; @mongo_connection ||= Mongo::Connection.new end
  def mongo; mongo_connection.db(db_name) end
  def enqueue(job, *data); Qu.enqueue job, db_name, *data end
end

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
  enqueue Find, params[:server]
  
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
  
  enqueue DocPull, @peer.name, @doc.name
  redirect to("/a/peers/#{@peer.name}")
end

post '/a/peers/:name/sync' do
  enqueue Sync, params[:name]
  
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
  enqueue Clone, params[:url]
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
    
    mongo["docs.#{import_peer["_name"]}"].insert import_json["docs"]
    
    redirect to("/a/peers/#{import_peer["_name"]}")
  rescue Zlib::GzipFile::Error , JSON::ParserError
    "Bad file"
  end
end

get '' do
  redirect to('/')
end

get '/index' do
  redirect to('/')
end

get '/' do
  @doc = DocIndex.new(mongo, :context => self)
  @name = @doc.name
  
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

get '/:doc.txt' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?

  content_type :txt
  @doc.to_txt
end

get '/:doc.reqif' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?

  content_type :txt
  @doc.to_reqif
end

get '/:doc.json' do
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

get '/:doc.or.gz' do
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

get '/:doc' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  @name = @doc.name
  
  haml :doc
end

get '/:doc/files/:file' do
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

get '/:doc/files/' do
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

post '/:doc/files/' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  
  upload_file = params[:file]
  not_found if upload_file.nil?

  @fs = Mongo::GridFileSystem.new(mongo)
  file = @fs.open("/d/" + params[:doc] + "/" + upload_file[:filename], "w") do |f|
    f.write upload_file[:tempfile].read
  end
  
  redirect to('/' + URI.escape(params[:doc]))
end

get '/:doc/requirements.json' do
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

post '/:doc/delete' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
 
  mongo["docs"].remove "_name" => @doc.name
  redirect to('/')
end

get '/:doc/edit' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  @name = @doc.name
  @content = @doc.content
  
  cache_control :no_cache
  haml :doc_edit
end

post '/:doc/edit' do
  doc_data = request.POST
  doc_data["_name"] = params[:doc]
  doc_data["date"] = Time.now.utc
  mongo["docs"].save doc_data

  redirect to('/' + URI.escape(params[:doc]))
end

get '/:doc/requirements.:link.csv' do
  @attribute = params[:link]
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?

  @reqs = @doc.requirements
  @reqs.each {|req|
    linked_reqs =  CreolaExtractURL.new(req[@attribute] || '').to_a
    req[@attribute] = linked_reqs.map {|req_name| Doc.new(mongo, req_name, :context => self) }
  }
  
  # List the attributes of a req
  get_req_attributes = lambda {|reqs| reqs.map {|req| req.attributes.keys}.flatten.uniq }
  
  @source_attributes = get_req_attributes.call(@reqs)
  @source_attributes.delete(@attribute)
  @linked_attributes = @reqs.map {|req| get_req_attributes.call(req[@attribute]) }.flatten.uniq

  haml :req_link_csv
end

get '/:doc/requirements' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  
  @attribute = params[:attributes]
  get_req_attributes = lambda {|reqs| reqs.map {|req| req.attributes.keys}.flatten.uniq }

  linked_attributes = @doc.requirements.map {|req|
    linked_reqs =  CreolaExtractURL.new(req[@attribute] || '').to_a
    get_req_attributes.call(linked_reqs.map {|req_name| Doc.new(mongo, req_name, :context => self) })
  }.flatten.uniq
  linked_attributes.push(*%w(date _name _content)) if not linked_attributes.empty?
  
  content_type :json
  linked_attributes.to_json
end

get '/:doc/requirements/next_name' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  
  requirement_list = @doc.requirement_list.sort
  requirement_list << params[:previous] if params[:previous] && !params[:previous].empty?
  
  last_req = requirement_list.last || @doc.name
  last_req = last_req + "-0" if not last_req[/\d+(?!.*\d+)/]
  last_req[/\d+(?!.*\d+)/] = last_req[/\d+(?!.*\d+)/].succ
  
  content_type :txt
  last_req
end

get '/:doc/define_matrix' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  
  @reqs = @doc.requirements
  # List the attributes of a req
  get_req_attributes = lambda {|reqs| reqs.map {|req| req.attributes.keys}.flatten.uniq }
  
  @source_attributes = get_req_attributes.call(@reqs) + %w(date _name _content)
  haml :define_matrix
end

get '/:doc/matrix' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist? || !params["columns"]
  
  @columns = params["columns"].split(",")
  @sorts = params["sorts"]
  @filters = (params["filters"] || "").split(",")
  @reqs = @doc.requirements
  reqsToDisplay = []
  
  to = []
  @columns.each {|c| to << c[/^\w+/] if c.include? "."}
  to.uniq!
  
  to.each do |attr|
    @reqs.each {|req|
      linked_reqs =  CreolaExtractURL.new(req[attr] || '').to_a
      linked_reqs.each {|req_name|
        req = req.clone
        @columns.each {|attr_name|
          if attr_name.include?(".")
            linked_req= Doc.new(mongo, req_name, :context =>self)
            req[attr_name] = linked_req[attr_name.match(/#{to}\.(\w+)/)[1]]
          end
        }
        reqsToDisplay << req
      }
      reqsToDisplay << req if linked_reqs.empty?
    }
  end
  reqsToDisplay += @reqs if to.empty? 
 
  if !@sorts.nil? 
    @sorts.reverse.each do |sort|
      sortAttr=sort.split(",")[0]
      sortOrder=sort.split(",")[1]
      if sortOrder == "Increasing"
         reqsToDisplay = reqsToDisplay.sort do |req1,req2|
           # Using Array = Array.sort instead of Array.sort! because Array.sort! provides an erroneous result (it seems sort! updates the table order during its execution)
           [req1[sortAttr].to_s, reqsToDisplay.index(req1)] <=> [req2[sortAttr].to_s, reqsToDisplay.index(req2)]
        end
      elsif sortOrder == "Decreasing"
         reqsToDisplay = reqsToDisplay.sort do |req1,req2|
           # Using Array = Array.sort instead of Array.sort! because Array.sort! provides an erroneous result (it seems sort! updates the table order during its execution)
           [req2[sortAttr].to_s, reqsToDisplay.index(req1)] <=> [req1[sortAttr].to_s, reqsToDisplay.index(req2)]
        end
      else
        # Do Nothing
      end
    end
  end

  @reqs = reqsToDisplay

  haml :matrix
end

get '/:doc/to/:link' do
  @attribute = params[:link]
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?

  @reqs = @doc.requirements
  @reqs.each {|req|
    linked_reqs =  CreolaExtractURL.new(req[@attribute] || '').to_a
    req[@attribute] = linked_reqs.map {|req_name| Doc.new(mongo, req_name, :context => self) }
  }
  
  # List the attributes of a req
  get_req_attributes = lambda {|reqs| reqs.map {|req| req.attributes.keys}.flatten.uniq }
  
  @source_attributes = get_req_attributes.call(@reqs)
  @source_attributes.delete(@attribute)
  @linked_attributes = @reqs.map {|req| get_req_attributes.call(req[@attribute]) }.flatten.uniq

  haml :req_link
end

get '/:doc/from/:link' do
  @attribute = params[:link]
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  
  # Get the name of all the docs (hence all requirements) from the database
  reqs_list = @doc.docs

  # Get all the docs (hence all requirements) for which @attribute is defined
  db_reqs = mongo["docs"].find({@attribute => { "$exists" => "true" }}, {:sort => ["date", :desc]}).to_a

  @l0_reqs_name = @doc.requirement_list
  @l0_reqs = @doc.requirements

  # Get the last version of requirements that have a link to a requirement from the current document
  @l1_reqs = reqs_list.map {|req_name|
    if req = db_reqs.find {|creq| creq["_name"] == req_name}
      if @l0_reqs_name.find {|l0_req_name| req[@attribute].include? l0_req_name}
        Doc.new(mongo, req_name, :context => self)
      end
    end
  }.compact

  # List the attributes of a req
  get_req_attributes = lambda {|reqs| reqs.map {|req| Hash[req.attributes].keys}.flatten.uniq}
  
  @l0_attributes = get_req_attributes.call(@l0_reqs)
  @l1_attributes = get_req_attributes.call(@l1_reqs)

  haml :req_from_link
end

get '/:doc/history.json' do
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

get '/:doc/history.rss' do
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
  @doc_diffs = @docs.each_cons(2).map {|doc_a, doc_b| DocDiff.new(doc_b, doc_a, :context => self, :slave_parser => ContentDiffHTMLNoClass.new) }
  
  content_type :rss
  haml :doc_history_rss
end

get '/:doc/history' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?

  @dates = mongo["docs"].find({"_name" => params[:doc]}, {:fields => "date", :sort => ["date", :asc]}).map {|doc| doc["date"]}
  req_names = @doc.requirement_list
  @dates.concat mongo["docs"].find({
    "_name" => {"$in" => req_names},
    "date"=> {"$gt" => @dates[0]}
   }, {:fields => "date"}).map {|req| req["date"]}
  @dates = @dates.sort.reverse
  @name = params[:doc]
  
  haml :doc_history
end

get '/:doc/:date.txt' do
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @doc = Doc.new(mongo, params[:doc], :date => @date, :context => self)
  not_found if !@doc.exist?
  
  content_type :txt
  @doc.to_txt
end

get '/:doc/:date.json' do
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @doc = Doc.new(mongo, params[:doc], :date => @date, :context => self)
  not_found if !@doc.exist?
  
  content_type :json
  @doc.to_json
end

get '/:doc/:date' do
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @doc = Doc.new(mongo, params[:doc], :date => @date, :context => self)
  not_found if !@doc.exist?
  
  @name = params[:doc]
  haml :doc_version
end

get '/:doc/:date/diff' do
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

end
