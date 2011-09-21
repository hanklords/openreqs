require 'sinatra'
require 'haml'
require 'creole'
require 'mongo'

ROOT_PATH = ENV['HOME'] + '/openreqs/'
DB = Mongo::Connection.new.db("openreqs")

# Creole extensions
class DocReqParser < Creole::Parser
  def initialize(doc, options = {})
    @doc = doc
    super(@doc["_content"], options)
  end
  
  def make_explicit_anchor(uri, text)
    if uri =~ /\.req$/ 
      if req = DB["requirements"].find_one("_name" => uri)
        ReqParser.new(req).to_html
      else
        "<a href=\"#{@doc["_name"]}/#{uri}/add\">#{uri}</a><br/>"
      end
    else
      super
    end
  end
end

class ReqParser < Creole::Parser
  def initialize(req, options = {})
    @req = req
    super(@req["_content"], options)
  end

  def to_html
    attributes = @req.reject {|k,v| k =~ /^_/}
    "<h2>#{@req["_name"]}</h2><ul>" + 
        "<a href=\"#{@req["_doc"]}/#{@req["_name"]}/edit\">edit</a><br/>" + 
        attributes.map {|k,v| "<li>#{k}: #{v}</li>"}.join + "</ul>" + super
  end
end

# web application

before {content_type :html, :charset => 'utf-8'}

get '/' do
  haml %q{
%ul
  - DB["docs"].find.each do |doc|
    - name = doc['_name']
    %li
      %a(href=name)= name
}
end

get '/:doc' do
  doc = DB["docs"].find_one("_name" => params[:doc])
  parser = DocReqParser.new(doc)
  "<a href=\"#{params[:doc]}/edit\">edit</a><br/>" + parser.to_html
end

get '/:doc/edit' do
  doc = DB["docs"].find_one("_name" => params[:doc])
  @_content = doc["_content"]
  haml %q{
%form(method="post")
  %textarea(name="content" cols=80 rows=40)
    = @_content
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
  %textarea(name="content" cols=80 rows=40)
    = @_content
  %p
  %input(type="submit" value="Sauver")
}
end

post '/:doc/:req/add' do
  req = {"_name" => params[:req], "_doc" => params[:doc], "_content" => params[:content]}
  DB["requirements"].insert req
  
  redirect to('/' + params[:doc])
end

post '/:doc/:req/delete' do
  DB["requirements"].remove("_name" => params[:req], "_doc" => params[:doc])
  
  redirect to('/' + params[:doc])
end

get '/:doc/:req/edit' do
  doc = DB["requirements"].find_one("_doc" => params[:doc], "_name" => params[:req])
  @_content = doc["_content"]
  haml %q{
%form(method="post")
  %textarea(name="content" cols=80 rows=40)
    = @_content
  %p
  %input(type="submit" value="Sauver")
  
%form(method="post" action="delete")
  %input(type="submit" value="Supprimer")
}
end

post '/:doc/:req/edit' do
  DB["requirements"].update({"_doc" => params[:doc], "_name" => params[:req]}, {"$set" => {"_content" => params[:content]}})
  
  redirect to('/' + params[:doc])
end
