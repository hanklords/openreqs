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
          break ReqParser.new(req).to_html
        end
      when :doc
        if doc = DB["docs"].find_one("_name" => uri)
          break super(uri, text)
        end
      when :new_req
        uri = escape_url(uri) + "/add_req"
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

class ReqParser
  Template = File.dirname(__FILE__) + '/views/default/req_inline.haml'
  def initialize(req)
    @req = req
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
    @engine.render(Object.new, {:name => @req["_name"], :attributes => @attributes, :content => @parser.to_html})
  end
end

# web application
set :views, Proc.new { File.join(root, "views", "default") }
before {content_type :html, :charset => 'utf-8'}

set(:mode) do |mode| 
  condition {
    case mode
    when :doc
      !@doc.nil?
    when :req
      !@req.nil?
    else
      false
    end
  }
end

['/:doc', '/:doc/edit'].each {|path|
  before path do
    @doc = DB["docs"].find_one("_name" => params[:doc])
    if @doc.nil?
      @req = DB["requirements"].find_one("_name" => params[:doc])
    end
  end
}

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
  @content = DocReqParser.new(doc["_content"], :find_local_link => [:doc, :new_doc]).to_html
  haml :index
end

post '/index/edit' do
  DB["docs"].update({"_name" => 'index'}, {"$set" => {"_content" => params[:content]}})
  redirect to('/')
end

get '/:doc', :mode => :doc do
  @name = @doc["_name"]
  @content = DocReqParser.new(@doc["_content"], :find_local_link => [:req_inline, :doc, :new_req]).to_html
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
  @content = @doc["_content"]
  haml :doc_edit
end

post '/:doc/edit', :mode => :doc do
  DB["docs"].update({"_name" => params[:doc]}, {"$set" => {"_content" => params[:content]}})
  redirect to('/' + params[:doc])
end

get '/:doc/req_add' do
  haml :doc_req_add
end

post '/:doc/req_add' do
  req = {"_name" => params[:doc], "_content" => params[:content], "date" => Time.now.iso8601}
  DB["requirements"].insert req
  
  redirect to('/' + params[:doc])
end

get '/:doc', :mode => :req do
  @name = @req["_name"]
  @content = ReqParser.new(@req)
  
  @content.to_html
end

get '/:doc/edit', :mode => :req do
  cache_control :no_cache
  @content = @req["_content"]
  @attributes = @req.reject {|k,v| k =~ /^_/}
  
  haml :doc_req_edit
end

post '/:doc/edit', :mode => :req do
  set, unset = {"_content" => params[:content]}, {}
  set[params[:key]] = params[:value] if !params[:key].empty? && !params[:value].empty?
  unset[params[:key]]= 1 if !params[:key].empty? && params[:value].empty?
  DB["requirements"].update({"_name" => params[:doc]}, {"$set" => set, "$unset" => unset})
  
  redirect to('/' + params[:doc])
end
