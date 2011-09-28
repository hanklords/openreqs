require 'sinatra'
require 'haml'
require 'creole'
require 'mongo'
require 'time'

ROOT_PATH = ENV['HOME'] + '/openreqs/'
DB = Mongo::Connection.new.db("openreqs")

# Creole extensions
class DocReqParser < Creole::Parser
  attr_reader :content
  def initialize(content, options = {})
    @content, @options = content, options
    @options[:find_local_link] ||= []
    @options[:find_local_link] << :default
    @extensions = @no_escape = true
    super(content)
  end
  
  def make_explicit_anchor(uri, text)
    @options[:find_local_link].each { |method|
      case method
      when :req_inline
        if req = DB["requirements"].find_one("_name" => uri)
          break ReqParser.new(req, @options[:context]).to_html
        end
      when :doc
        if doc = DB["docs"].find_one("_name" => uri)
          break super(uri, text)
        end
      when :new_req
        if context = @options[:context]
          context_name = context["_name"]
        else
          context_name = 'index'
        end
        uri = escape_url(context_name) + "/" + escape_url(uri) + "/add"
        break super(uri, text)
      when :new_doc
        uri = escape_url(uri) + "/add"
        break super(uri, text)
      when :default
        break super(uri, text)
      else
        raise "Unrecognized local link find method : #{method}"
      end
    }
  end
  
  # Ugly hack so the parser does not enclose the resulting html in "<p>...</p> tags"
  def parse_block(*args) 
    @p = true
    super
  end
end

class AttributeReqParser
  attr_reader :content
  def initialize(content); @content = content end
  def to_html; DocReqParser.new(@content.to_s).to_html end
end

class ReqParser
  Template = File.dirname(__FILE__) + '/views/default/req.haml'
  def initialize(req, doc = nil)
    @req, @doc = req, doc
    @engine = Haml::Engine.new(File.read(Template))
    @parser = DocReqParser.new(@req["_content"])
    @attributes = {}
    if @req["date"]
      @req["date"] = Time.xmlschema(@req["date"]) rescue Time.parse(@req["date"])
    end
    @req.each {|k,v|
      next if k =~ /^_/
      @attributes[k] = DocReqParser.new(v)
    }
    
  end

  def to_html
    @engine.render(Object.new, {:doc => @doc["_name"],:name => @req["_name"], :attributes => @attributes, :content => @parser.to_html})
  end
end

# web application
set :views, Proc.new { File.join(root, "views", "default") }
before {content_type :html, :charset => 'utf-8'}

get '/index' do
  redirect to('/')
end

get '/' do
  doc = DB["docs"].find_one("_name" => 'index')
  if doc.nil?
    doc = {"_name" => 'index', "_content" => ''}
    DB["docs"].insert doc
  end
  
  @name = doc["_name"]
  @content = DocReqParser.new(doc["_content"], :find_local_link => [:doc, :new_doc], :context => doc).to_html
  haml :index
end

post '/index/edit' do
  DB["docs"].update({"_name" => 'index'}, {"$set" => {"_content" => params[:content]}})
  redirect to('/')
end

get '/:doc' do
  doc = DB["docs"].find_one("_name" => params[:doc])
  return not_found if doc.nil?

  @name = doc["_name"]
  @content = DocReqParser.new(doc["_content"], :find_local_link => [:req_inline, :doc, :new_req], :context => doc).to_html
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

get '/:doc/edit' do
  cache_control :no_cache
  doc = DB["docs"].find_one("_name" => params[:doc])
  return not_found if doc.nil?
  
  @content = doc["_content"]
  haml :doc_edit
end

post '/:doc/edit' do
  DB["docs"].update({"_name" => params[:doc]}, {"$set" => {"_content" => params[:content]}})
  redirect to('/' + params[:doc])
end

get '/:doc/:req/add' do
  haml :doc_req_add
end

post '/:doc/:req/add' do
  req = {"_name" => params[:req], "_content" => params[:content], "date" => Time.now.iso8601}
  DB["requirements"].insert req
  
  redirect to('/' + params[:doc])
end

post '/:doc/:req/delete' do
  DB["requirements"].remove("_name" => params[:req])
  
  redirect to('/' + params[:doc])
end

get '/:doc/:req/edit' do
  doc = DB["requirements"].find_one("_name" => params[:req])
  @content = doc["_content"]
  @attributes = doc.reject {|k,v| k =~ /^_/}
  
  haml :doc_req_edit
end

post '/:doc/:req/edit' do
  set, unset = {"_content" => params[:content]}, {}
  set[params[:key]] = params[:value] if !params[:key].empty? && !params[:value].empty?
  unset[params[:key]]= 1 if !params[:key].empty? && params[:value].empty?
  
  DB["requirements"].update({"_name" => params[:req]}, {"$set" => set, "$unset" => unset})
  
  redirect to('/' + params[:doc])
end
