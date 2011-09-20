require 'haml'
require 'creole'

ROOT_PATH = ENV['HOME'] + '/openreqs/'

class Req
  attr_reader :id, :header, :content
  def initialize(req)
    @file = req
    @id = File.basename(@file, '.req')
    parse_req(File.read(req))
  end
  
  def parse_req(text)
    @header = {}
    @content = ''
    reading_header = true
    
    text.each_line do |line|
      line.rstrip!
      reading_header = false if line =~ /^$/
      
      if reading_header
        k,v = line.split(':', 2)
        @header[k] = v  # TODO: multiline attributes
      else
        @content << line
      end
    end
  end
  
end

# Creole extensions
class DocReqParser < Creole::Parser
  def initialize(doc, options = {})
    @doc = doc
    @doc_dir = File.dirname(@doc) + '/'
    super(File.read(doc), options)
  end
  
  def make_explicit_anchor(uri, text)
    if uri =~ /\.req$/ && File.file?(@doc_dir + uri)
      ReqParser.new(@doc_dir + uri).to_html
    else
      super
    end
  end
end

class ReqParser < Creole::Parser
  def initialize(doc, options = {})
    @doc = doc
    @doc_dir = File.dirname(@doc) + '/'
    @req = Req.new(@doc)
    super(@req.content, options)
  end

  def to_html
    "<h2>#{@req.id}</h2><ul>" + @req.header.map {|k,v| "<li>#{k}: #{v}</li>"}.join + "</ul>" + super
  end
end

# web application

before {content_type :html, :charset => 'utf-8'}

get '/' do
  haml %q{
%ul
  - Dir[ROOT_PATH + '*'].each do |file|
    - next if not File.directory?(file)
    - filename = File.basename(file)
    %li
      %a(href=filename)= filename
    
}
end

get '/:doc/edit' do
  @doc_content = File.read(ROOT_PATH + params[:doc] + '/index.creole')
  haml %q{
%form(method="post")
  %textarea(name="content" cols=80 rows=40)
    = @doc_content
  %p
  %input(type="submit" value="Sauver")
}
end

post '/:doc/edit' do
  File.open(ROOT_PATH + params[:doc] + '/index.creole', 'w') do |doc|
    doc.write params[:content]
  end
  
  redirect to('/' + params[:doc])
end

get '/:doc' do
  parser = DocReqParser.new(ROOT_PATH + params[:doc] + '/index.creole')
  "<a href=\"#{params[:doc]}/edit\">edit</a><br/>" + parser.to_html
end
