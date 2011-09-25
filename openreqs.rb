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
    @doc = doc
    super(@doc["_content"], options)
  end
  
  def make_explicit_anchor(uri, text)
    if req = DB["requirements"].find_one("_name" => uri)
      ReqParser.new(@doc, req).to_html
    elsif doc = DB["docs"].find_one("_name" => uri)
      super
    else
      super(escape_url(@doc["_name"]) + "/" + escape_url(uri) + "/add", text)
    end
  end
end

class IndexDocReqParser < Creole::Parser
  def make_local_link(link)
    if DB["docs"].find_one("_name" => link)
      escape_url(link)
    else
      escape_url(link) + "/add"
    end
  end
end

class ReqParser < Creole::Parser
  def initialize(doc, req, options = {})
    @doc, @req = doc, req
    super(@req["_content"], options)
  end

  def to_html
    attributes = @req.reject {|k,v| k =~ /^_/}
    "<h2>#{@req["_name"]}</h2><ul>" + 
        "<a href=\"#{@doc["_name"]}/#{@req["_name"]}/edit\">edit</a><br/>" + 
        attributes.map {|k,v| "<li>#{k}: #{v}</li>"}.join + "</ul>" + super
  end
end

# web application

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
  
  parser = IndexDocReqParser.new(doc["_content"])
  "<a href=\"index/edit\">edit</a><br/>" + parser.to_html
end

post '/index/edit' do
  DB["docs"].update({"_name" => 'index'}, {"$set" => {"_content" => params[:content]}})
  redirect to('/')
end

get '/:doc' do
  doc = DB["docs"].find_one("_name" => params[:doc])
  return not_found if doc.nil?

  parser = DocReqParser.new(doc)
  "<a href=\"#{params[:doc]}/edit\">edit</a><br/>" + parser.to_html
end

get '/:doc/add' do
    haml %q{
%form(method="post")
  %textarea(name="content" cols=80 rows=40)= @_content
  %p
  %input(type="submit" value="Sauver")
}
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
  
  @_content = doc["_content"]
  haml %q{
%form(method="post")
  %textarea(name="content" cols=80 rows=40)= @_content
  %p
  %input(type="submit" value="Sauver")
}
end

post '/:doc/edit' do
  DB["docs"].update({"_name" => params[:doc]}, {"$set" => {"_content" => params[:content]}})
  redirect to('/' + params[:doc])
end

get '/:doc/:req/add' do
    haml %q{
%form(method="post")
  %textarea(name="content" cols=80 rows=40)= @_content
  %p
  %input(type="submit" value="Sauver")
}
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
  @_content = doc["_content"]
  @attributes = doc.reject {|k,v| k =~ /^_/}
  
  haml %q{
%form(method="post")
  %h2 Attributes
  %ul
    - @attributes.each do |k,v| 
      %li #{k}: #{v}
    %li
      %input(name="key")
      \:
      %input(name="value")
  %h2 Text
  %textarea(name="content" cols=80 rows=40)= @_content
  %p
  %input(type="submit" value="Sauver")
  
%form(method="post" action="delete")
  %input(type="submit" value="Supprimer")
}
end

post '/:doc/:req/edit' do
  set, unset = {"_content" => params[:content]}, {}
  set[params[:key]] = params[:value] if !params[:key].empty? && !params[:value].empty?
  unset[params[:key]]= 1 if !params[:key].empty? && params[:value].empty?
  
  DB["requirements"].update({"_name" => params[:req]}, {"$set" => set, "$unset" => unset})
  
  redirect to('/' + params[:doc])
end
