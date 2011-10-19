require 'sinatra'
require 'haml'
require 'creola/html'
require 'creola/txt'
require 'mongo'
require 'diff/lcs'
require 'time'
require 'json'
require 'openssl'
require 'qu-mongo'

configure do
  set :mongo, Mongo::Connection.new.db("openreqs")
   mime_type :pem, "application/x-pem-file"
end

helpers do
  def mongo; settings.mongo end
end

# Creole extensions
class CreolaExtractURL < Creola
  def initialize(*args);  super; @links = [] end
  alias :to_a :render
  def root(content); @links end
  def link(url, text, namespace); @links << url end
end

class Doc
  attr_reader :name, :options
  def initialize(db, name, options = {})
    @db, @name, @options = db, name, options
    @options[:date] ||= Time.now.utc + 1
    @doc = @db["docs"].find_one(
      {"_name" => @name,
       "date" => {"$lte" => @options[:date]}
      }, {:sort => ["date", :desc]}
    )
  end
  
  def exist?; !@doc.nil? end
  def [](attr); exist? ? @doc[attr] : nil end
  def date; self["date"] end
  def content; self["_content"] || '' end
  
  def docs; @all_docs ||= @db["docs"].find({}, {:fields => "_name"}).map {|doc| doc["_name"]}.uniq end
 
  def requirement_list
    @requirement_list ||= CreolaExtractURL.new(content).to_a
  end
  
  def find_requirements
    @all_reqs ||= @db["requirements"].find(
      { "_name" => {"$in" => requirement_list},
        "date"=> {"$lt" => @options[:date]}
      }, {:sort => ["date", :desc]}
    ).to_a
  end
  
  def requirements
    @requirements ||= find_requirements.reduce({}) {|m, req|
      req_name = req["_name"]
      m[req_name] ||= Req.new(@db, nil, :req => req, :context => @options[:context]) if req["date"] < @options[:date]
      m
    }
  end
  
  def to_json(*args)
    doc = @doc.clone
    doc.delete("_id")
    doc["_reqs"] = requirements.values
    doc.to_json
  end
  
  def to_json_with_history
    @db["docs"].find({
        "_name" => @name,
        "date" => {"$lte" => @options[:date]}
      }, {:sort => ["date", :desc]}
    ).to_a.each {|doc| doc.delete("_id")}.to_json    
  end
  
  def to_hash; @doc end
  def to_html
    DocHTML.new(content,
      :docs => docs,
      :requirements => requirements,
      :context => @options[:context]
    ).to_html 
  end
  def to_txt; DocParserTxt.new(content, :name => name, :requirements => requirements).to_txt end
end
      
class DocIndex < Doc
  def initialize(db, options = {})
    super(db, 'index', options)
    if !exist?
      @doc = {"_name" => 'index', "_content" => '', "date" => Time.now.utc}
      @db["docs"].insert @doc
    end
  end
  
  def requirement_list; [] end
  def to_html; DocIndexHTML.new(content, :docs => docs, :context => @options[:context]).to_html end
end

class DocHTML < CreolaHTML
  def heading(level, text); super(level + 1, text) end
  def link(uri, text, namespace)
    context = @options[:context]
    
    if uri =~ %r{^(http|ftp)://}
      super(uri, text, namespace)
    elsif req = @options[:requirements][uri]
      ReqHTML.new(req, :context => context).to_html
    elsif @options[:docs].include? uri
      super(context.to("/d/#{uri}"), text || uri, namespace)
    else
      super(context.to("/r/#{uri}/add"), text || uri, namespace)
    end
  end
end

class DocIndexHTML < CreolaHTML
  def link(uri, text, namespace)
    context = @options[:context]
    
    if @options[:docs].include? uri
      super(context.to("/d/#{uri}"), text || uri, namespace)
    else
      super(context.to("/d/#{uri}/add"), text || uri, namespace)
    end
  end
end

class DocParserTxt < CreolaTxt
  def heading(level, text); super(level + 1, text) end
  def link(uri, text, namespace)
    if req = @options[:requirements][uri]
      req.to_txt + "\n"
    else
      super(uri, text, namespace)
    end
  end
  
  def to_txt; "= #{@options[:name]} =\n\n" + super end
end

class CreolaList < CreolaTxt
  def root(content); content.flatten end
  def to_a; render end
  undef_method :to_txt
end

class ContentDiff < CreolaHTML
  def initialize(old_creole, new_creole, options = {})
    @old_content = CreolaList.new(old_creole).to_a
    @new_content = CreolaList.new(new_creole).to_a
    super(nil, options)
  end
  
  def match(event)
    @discard_state = nil
    @state = tokenize_string(event.new_element, @state)
  end

  def discard_a(event)
    @discard_state = :remove
    @state = tokenize_string(event.old_element, @state)
  end

  def discard_b(event)
    @discard_state = :add
    @state = tokenize_string(event.new_element, @state)
  end
  
  def words(*words);
    case @discard_state
    when :remove
      %{<span class="remove">} + words.join + "</span>"
    when :add
      %{<span class="add">} + words.join + "</span>"
    else
      words.join
    end
  end;
  
  private
  def tokenize
    @state = State::Root.new(self)
    Diff::LCS.traverse_sequences(@old_content, @new_content, self)
    @state = @state.parse(:EOS, nil)
    root(@state.finish)
  end
end

class DocDiff < ContentDiff
  def initialize(doc_old, doc_new, options = {})
    @doc_old, @doc_new = doc_old, doc_new
    super(@doc_old.content, @doc_new.content, options)
  end
  
  def heading(level, text); super(level + 1, text) end
  def link(uri, text, namespace)
    req_old = @doc_old.requirements[uri]
    req_new = @doc_new.requirements[uri]
    if req_old || req_new
      case @discard_state
      when :remove
        ReqDiff.new(req_old, EmptyReq.new, @options).to_html
      when :add
        ReqDiff.new(EmptyReq.new, req_new, @options).to_html
      else
        ReqDiff.new(req_old, req_new, @options).to_html
      end
    elsif @doc_old.docs.include?(uri) || @doc_new.docs.include?(uri)
      super(@options[:context].to("/d/#{uri}"), text || uri, namespace)
    else
      super(uri, text, namespace)
    end
  end
  
end

class ReqDiff
  TEMPLATE = 'req_inline.haml'
  def initialize(req_old, req_new, options = {})
    @req_old, @req_new, @options = req_old, req_new, options
    @context = @options[:context]
    @content = ContentDiff.new(req_old.content, req_new.content)
  end

  def attributes
    @attributes ||= Hash[@req_new.attributes.map {|k,v| [k, CreolaHTML.new(v)]}]
  end
  
  attr_reader :content
  def name; @req_new.name || @req_old.name end
  def date; @req_new.date || @req_old.date end
        
  def to_html
    template = File.join(@context.settings.views, TEMPLATE)
    engine = Haml::Engine.new(File.read(template))
    @context.instance_variable_set :@reqp, self
    engine.render(@context)
  end
end

class Req
  attr_reader :options
  def initialize(db, name, options = {})
    @db, @options = db, options
    @options[:date] ||= Time.now.utc + 1
    @req = @options[:req]
    
    if @req.nil? 
      @req = @db["requirements"].find_one(
        {"_name" => name,
        "date" => {"$lt" => @options[:date]}
        }, {:sort => ["date", :desc]}
      )
    end
  end
  
  def attributes
    exist? ? @req.select {|k,v| k !~ /^_/ && k != "date" } : []
  end
  
  def exist?; !@req.nil? end
  def [](attr); exist? ? @req[attr] : nil end
  def date; self["date"] end
  def content; self["_content"] || '' end
  def name; self["_name"] end
  def to_hash; @req end
  def to_txt
    str = "==== #{name} ====\n\n"
    str << content << "\n\n"
    str << "* date: #{date}\n"
    attributes.each {|k, v|
      str << "* #{k}: #{v}\n"
    }
    str << "\n"
  end
  
  def to_json(*args)
    req = @req.clone
    req.delete("_id")
    req.to_json
  end

  def to_json_with_history
    @db["requirements"].find({
        "_name" => name,
        "date" => {"$lt" => @options[:date]}
      }, {
        :sort => ["date", :desc]}
    ).to_a.each {|req| req.delete("_id")}.to_json
  end
end

class EmptyReq < Req
  def initialize; end
end

class ReqHTML
  TEMPLATE = 'req_inline.haml'
  def initialize(req, options = {})
    @req, @options = req, options
    @context = @options[:context]
  end
  
  def attributes
    @attributes ||= Hash[@req.attributes.map {|k,v| [k, CreolaHTML.new(v)]}]
  end
  
  def name; @req.name end
  def date; @req.date end
  def content; CreolaHTML.new(@req.content) end
    
  def to_html
    template = File.join(@context.settings.views, TEMPLATE)
    engine = Haml::Engine.new(File.read(template))
    @context.instance_variable_set :@reqp, self
    engine.render(@context)
  end
end


# web application
set :views, Proc.new { File.join(root, "views", "default") }
before {content_type :html, :charset => 'utf-8'}

get '/a/key.pem' do
  content_type :pem
  self_peer = mongo["peers"].find_one("_name" => "self")
  if self_peer.nil?
    gen_key = OpenSSL::PKey::RSA.new(2048)
    self_peer = {"_name" => "self", "private_key" => gen_key.to_pem, "key" => gen_key.public_key.to_pem}
    mongo["peers"].save self_peer
  end

  key = OpenSSL::PKey::RSA.new(self_peer["key"])
  key.to_pem
end

post '/a/peers/register' do
  user, name, key = params[:user], params[:name], params[:key]
  error 400, "user not provided in register request" if user.nil?
  error 400, "name not provided in register request" if name.nil?
  if key.nil? || !key.is_a?(Hash) || key[:tempfile].nil?
    error 400, "key not provided in register request"
  end

  peer_request = {"date" => Time.now.utc,
    "ip" => request.ip, "user_agent" => request.user_agent,
    "user" => user, "_name" => name,
    "key" => key[:tempfile].read
  }
  ""
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
  
  haml :index
end

get '/d.json' do
  content_type :json
  mongo["docs"].find({}, {:fields => "_name"}).map {|d| d["_name"]}.uniq.to_json
end

get '/d/:doc.txt' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?

  content_type :txt
  @doc.to_txt
end

get '/d/:doc.json' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  
  content_type :json
  params[:with_history] == "1" ? @doc.to_json_with_history : @doc.to_json
end

get '/d/:doc' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  @name = @doc.name
  
  haml :doc
end

get '/d/:doc/add' do
  @name = params[:doc]
  
  haml :doc_add
end

post '/d/:doc/add' do
  doc = {"_name" => params[:doc], "_content" => params[:content]}
  mongo["docs"].insert doc
  
  redirect to('/d/' + params[:doc])
end

get '/d/:doc/edit' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  not_found if !@doc.exist?
  @name = @doc.name
  @content = @doc.content
  
  cache_control :no_cache
  haml :doc_edit
end

post '/d/:doc/edit' do
  @doc = Doc.new(mongo, params[:doc], :context => self)
  doc_data = @doc.to_hash
  doc_data.delete "_id"
  doc_data["date"] = Time.now.utc
  doc_data["_content"] = params[:content]
  mongo["docs"].save doc_data

  redirect to('/d/' + params[:doc])
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

get '/r/:req/add' do
  haml :doc_req_add
end

post '/r/:req/add' do
  req = {"_name" => params[:doc], "_content" => params[:content], "date" => Time.now.utc}
  mongo["requirements"].insert req
  
  redirect to('/r/' + params[:doc])
end

get '/r/:req.json' do
  @req = Req.new(mongo, params[:req], :context => self)
  not_found if !@req.exist?

  content_type :json
  params[:with_history] == "1" ? @req.to_json_with_history : @req.to_json
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
  not_found if !@req.exist?

  cache_control :no_cache
  haml :doc_req_edit
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
  req_data["date"] = Time.now.utc
  req_data["_content"] = params[:content]
  if !params[:key].empty?
    if !params[:value].empty?
      req_data[params[:key]] = params[:value]
    else
      req_data.delete params[:key]
    end
  end
  
  mongo["requirements"].save req_data
  
  redirect to('/r/' + params[:req])
end
