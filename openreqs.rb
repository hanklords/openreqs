lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'sinatra'
require 'haml'
require 'creola/html'
require 'creola/txt'
require 'mongo'
require 'diff/lcs'
require 'time'

DB = Mongo::Connection.new.db("openreqs")

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
  def content; self["_content"] end
  
  def docs; @all_docs ||= @db["docs"].find({}, {:fields => "_name"}).map {|doc| doc["_name"]}.uniq end
 
  def requirement_list
    @requirement_list ||= CreolaExtractURL.new(content).to_a
  end
  
  def find_requirements
    @all_reqs ||= @db["requirements"].find(
      { "_name" => {"$in" => requirement_list},
        "date"=> {"$lt" => @options[:date]}
      }, {:sort => ["date", :desc]}
    )
  end
  
  def requirements
    @requirements ||= find_requirements.reduce({}) {|m, req|
      req_name = req["_name"]
      m[req_name] ||= Req.new(@db, nil, :req => req, :context => @options[:context]) if req["date"] < @options[:date]
      m
    }
  end
      
  def to_hash; @doc end
  def to_html
    DocHTML.new(content,
      :docs => docs,
      :requirements => requirements,
      :context => @options[:context]
    ).to_html 
  end
  def to_txt; DocParserTxt.new(content, :requirements => requirements).to_txt end
end
      
class DocIndex < Doc
  def initialize(db, options = {})
    super(db, 'index', options)
    if !exist?
      @doc = {"_name" => 'index', "_content" => ''}
      @db["docs"].insert @doc
    end
  end
  
  def requirement_list; [] end
  def to_html; DocIndexHTML.new(content, :docs => docs).to_html end
end

class DocHTML < CreolaHTML
  def link(uri, text, namespace)
    if uri =~ %r{^(http|ftp)://}
      super(uri, text, namespace)
    elsif req = @options[:requirements][uri]
      ReqHTML.new(req, :context => @options[:context]).to_html
    elsif @options[:docs].include? uri
      super(uri, text, namespace)
    else
      text ||= uri
      uri = uri + "/add_req"
      super(uri, text, namespace)
    end
  end
end

class DocIndexHTML < CreolaHTML
  def link(uri, text, namespace)
    if @options[:docs].include? uri
      super(uri, text, namespace)
    else
      text ||= uri
      uri = uri + "/add"
      super(uri, text, namespace)
    end
  end
end

class DocParserTxt < CreolaTxt
  def link(uri, text, namespace)
    if req = @options[:requirements][uri]
      str = "==== #{req.name} ====\n\n"
      str << req.content << "\n\n"
      str << "* date: #{req.date}\n"
      req.attributes.each {|k, v|
        str << "* #{k}: #{v}\n"
      }
      str << "\n"
    else
      super(uri, text, namespace)
    end
  end
end

class CreolaList < CreolaTxt
  def root(content); content.flatten end
  def to_a; render end
  undef_method :to_txt
end

class ContentDiff < CreolaHTML
  def initialize(old_content, new_content, options = {})
    @old_content, @new_content = old_content, new_content
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
    super(CreolaList.new(@doc_old.content).to_a, CreolaList.new(@doc_new.content).to_a, options)
  end
  
  def link(uri, text, namespace)
    req_old = @doc_old.requirements[uri]
    req_new = @doc_new.requirements[uri]
    if req_old || req_new
      case @discard_state
      when :remove
        ReqHTML.new(req_old, :context => @options[:context]).to_html
      when :add
        ReqHTML.new(req_new, :context => @options[:context]).to_html
      else
        ReqDiff.new(req_old, req_new, @options).to_html
      end
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
    @content = ContentDiff.new(CreolaList.new(req_old.content).to_a, CreolaList.new(req_new.content).to_a)
  end

  def attributes
    @attributes ||= Hash[@req_new.attributes.map {|k,v| [k, CreolaHTML.new(v)]}]
  end
  
  attr_reader :content
  def name; @req_new.name end
  def date; @req_new.date end
        
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
        "date" => {"$lte" => @options[:date]}
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
  def content; self["_content"] end
  def name; self["_name"] end
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

set(:mode) do |mode| 
  condition {
    case mode
    when :doc
      @doc.exist?
    when :req
      !@req.nil?
    else
      false
    end
  }
end

['/:doc', '/:doc.*', '/:doc/*'].each {|path|
  before path do
    @doc = Doc.new(DB, params[:doc], :context => self)
    if !@doc.exist?
      @req = Req.new(DB, params[:doc], :context => self)
    end
  end
}

get '' do
  redirect to('/')
end

get '/index' do
  redirect to('/')
end

get '/' do
  @doc = DocIndex.new(DB)
  @name = @doc.name
  haml :index
end

get '/:doc.txt', :mode => :doc do
  content_type :txt
  @doc.to_txt
end

get '/:doc', :mode => :doc do
  @name = @doc.name
  haml :doc
end

get '/:doc/add' do
  haml :doc_add
end

post '/:doc/add' do
  doc = {"_name" => params[:doc], "_content" => params[:content]}
  DB["docs"].insert doc
  
  redirect to('/' + params[:doc])
end

get '/:doc/edit', :mode => :doc do
  cache_control :no_cache
  @content = @doc.content
  haml :doc_edit
end

post '/:doc/edit', :mode => :doc do
  doc_data = @doc.to_hash
  doc_data.delete "_id"
  doc_data["date"] = Time.now.utc
  doc_data["_content"] = params[:content]
  DB["docs"].save doc_data

  redirect to('/' + params[:doc])
end

get '/:doc/history', :mode => :doc do
  @dates = DB["docs"].find({"_name" => params[:doc]}, {:fields => "date", :sort => ["date", :asc]}).map {|doc| doc["date"]}
  req_names = CreolaExtractURL.new(@doc["_content"]).to_a
  @dates.concat DB["requirements"].find({
    "_name" => {"$in" => req_names},
    "date"=> {"$gt" => @dates[0]}
   }, {:fields => "date"}).map {|req| req["date"]}
  @dates = @dates.sort.reverse
  @name = params[:doc]
  
  haml :doc_history
end

get '/:doc/:date.txt', :mode => :doc do
  content_type :txt
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @doc = Doc.new(DB, params[:doc], :date => @date, :context => self)
  not_found if !@doc.exist?
  
  @doc.to_txt
end

get '/:doc/:date', :mode => :doc do
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @doc = Doc.new(DB, params[:doc], :date => @date, :context => self)
  not_found if !@doc.exist?
  
  @name = params[:doc]
  haml :doc
end

get '/:doc/:date/diff', :mode => :doc do
  @date = @date_a = Time.xmlschema(params[:date]) + 1 rescue not_found
  @doc_a = Doc.new(DB, params[:doc], :date => @date_a, :context => self)
  not_found if !@doc_a.exist?
  
  @date_b = @date_a - 1
  @doc_b = Doc.new(DB, params[:doc], :date => @date_b, :context => self)
  not_found if !@doc_b.exist?

  @name = params[:doc]
  @content = DocDiff.new(@doc_b, @doc_a, :context => self).to_html
  haml :doc_diff
end

get '/:doc/add_req' do
  haml :doc_req_add
end

post '/:doc/add_req' do
  req = {"_name" => params[:doc], "_content" => params[:content], "date" => Time.now.utc}
  DB["requirements"].insert req
  
  redirect to('/' + params[:doc])
end

get '/:doc', :mode => :req do
  latest_doc = {}
  DB["docs"].find({}, {:fields => ["_name", "date"], :sort => ["date", :desc]}).each {|doc|
    latest_doc[doc["_name"]] ||= doc
  }
  latest = latest_doc.map {|k,v| v["_id"]}
  
  @origin = []
  DB["docs"].find({"_id" => {"$in" => latest}}, {:fields => ["_name", "_content"]}).each {|doc|
    if CreolaExtractURL.new(doc["_content"]).to_a.include? params[:doc]
      @origin << doc["_name"]
    end
  }
  
  ReqHTML.new(@req, :context => self).to_html
end

get '/:doc/edit', :mode => :req do
  cache_control :no_cache  
  haml :doc_req_edit
end

get '/:doc/history', :mode => :req do
  @dates = DB["requirements"].find({"_name" => params[:doc]}, {:fields => "date", :sort => ["date", :desc]}).map {|req| req["date"]}
  @name = params[:doc]
  
  haml :req_history
end

get '/:doc/:date', :mode => :req do
  @date = Time.xmlschema(params[:date]) + 1 rescue not_found
  @req = Req.new(DB, params[:doc], :date => @date, :context => self)
  not_found if @req.nil?
  
  ReqHTML.new(@req, :context => self).to_html
end

post '/:doc/edit', :mode => :req do
  @req.delete "_id"
  @req["date"] = Time.now.utc
  @req["_content"] = params[:content]
  if !params[:key].empty?
    if !params[:value].empty?
      @req[params[:key]] = params[:value]
    else
      @req.delete params[:key]
    end
  end
  
  DB["requirements"].save @req
  
  redirect to('/' + params[:doc])
end
