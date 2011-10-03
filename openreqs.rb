lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'sinatra'
require 'haml'
require 'creola/html'
require 'mongo'
require 'time'

DB = Mongo::Connection.new.db("openreqs")

# Creole extensions
class DocReqParser < CreolaHTML
  attr_reader :content
  def initialize(content, options = {})
    super
    @options[:find_local_link] ||= []
    @options[:find_local_link] << :default
  end
  
  def link(uri, text, namespace)
    @options[:find_local_link].each { |method|
      case method
      when :req_inline
        if req = DB["requirements"].find_one({"_name" => uri}, {:sort => ["date", :desc]})
          break ReqParser.new(req).to_html
        end
      when :doc
        if doc = DB["docs"].find_one("_name" => uri)
          break super(uri, text, namespace)
        end
      when :new_req
        text ||= uri
        uri = uri + "/add_req"
        break super(uri, text, namespace)
      when :new_doc
        uri = uri + "/add"
        break super(uri, text, namespace)
      when :default
        break super(uri, text, namespace)
      else
        raise "Unrecognized local link find method : #{method}"
      end
    }
  end
end

class ReqParser
  Template = File.dirname(__FILE__) + '/views/default/req_inline.haml'
  def initialize(req)
    @req = req
    @engine = Haml::Engine.new(File.read(Template))
    @parser = DocReqParser.new(@req["_content"])
    @attributes = {}
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

['/:doc', '/:doc/*'].each {|path|
  before path do
    @doc = DB["docs"].find_one("_name" => params[:doc])
    if @doc.nil?
      @req = DB["requirements"].find_one({"_name" => params[:doc]}, {:sort => ["date", :desc]})
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

get '/:doc/add_req' do
  haml :doc_req_add
end

post '/:doc/add_req' do
  req = {"_name" => params[:doc], "_content" => params[:content], "date" => Time.now.utc}
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

get '/:doc/history', :mode => :req do
  @dates = DB["requirements"].find({"_name" => params[:doc]}, {:fields => "date"}).map {|req| req["date"].iso8601}
  
  haml :req_history
end

get '/:doc/:date', :mode => :req do
  date = Time.xmlschema(params[:date]) + 1
  
  @req = DB["requirements"].find_one({"_name" => params[:doc], "date" => {"$lte" => date}}, {:sort => ["date", :desc]})
  @name = @req["_name"]
  @content = ReqParser.new(@req)
  
  @content.to_html
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
