require 'sinatra'
require 'haml'
require 'creole'
require 'mongo'
require 'time'

ROOT_PATH = ENV['HOME'] + '/openreqs/'
DB = Mongo::Connection.new.db("openreqs")

# Creole extensions
class DocReqParser < Creole::Parser
  def initialize(doc, options = {})
    @doc, @options = doc, options
    @options[:find_local_link] ||= []
    @options[:find_local_link] << :default
    @extensions = @no_escape = true
    super(@doc["_content"])
  end
  
  def make_explicit_anchor(uri, text)
    @options[:find_local_link].each { |method|
      case method
      when :req_inline
        if req = DB["requirements"].find_one("_name" => uri)
          break ReqParser.new(@doc, req).to_html
        end
      when :doc
        if doc = DB["docs"].find_one("_name" => uri)
          break super(uri, text)
        end
      when :new_req
        uri = escape_url(@doc["_name"]) + "/" + escape_url(uri) + "/add"
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
end

class ReqParser
  Template = File.dirname(__FILE__) + '/views/default/req.haml'
  def initialize(doc, req)
    @doc, @req = doc, req
    @engine = Haml::Engine.new(File.read(Template))
  end

  def to_html
    content = Creole::Parser.new(@req["_content"], :extensions => true).to_html
    attributes = @req.reject {|k,v| k =~ /^_/}
    if attributes["date"]
      attributes["date"] = Time.xmlschema(attributes["date"]) rescue Time.parse(attributes["date"])
    end
    @engine.render(Object.new, {:doc => @doc["_name"],:name => @req["_name"], :attributes => attributes, :content => content})
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
  @content = DocReqParser.new(doc, :find_local_link => [:doc, :new_doc]).to_html
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
  @content = DocReqParser.new(doc, :find_local_link => [:req_inline, :doc, :new_req]).to_html
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
