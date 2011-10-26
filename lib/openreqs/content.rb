require 'json'
require 'creola/html'
require 'creola/txt'

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
       "date" => {"$lt" => @options[:date]}
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
    doc["date"] = doc["date"].xmlschema(2)
    doc["_reqs"] = requirements.values
    doc.to_json
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

class DocVersions
  def initialize(db, options = {})
    @db, @options = db, options
    @docs = @db["docs"].find({"_name" => @options[:name]}, {:sort => ["date", :desc]})
  end
  
  def exist?; @docs.count > 0 end
  def name; @options[:name] end
  def dates; @docs.map {|doc| doc["date"]} end

  def to_json(*args)
    @docs.map {|doc|
      doc.delete("_id")
      doc["date"] = doc["date"].xmlschema(2)
      doc
    }.to_json
  end
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
    req["date"] = req["date"].xmlschema(2)
    req.to_json
  end
end

class ReqVersions
  def initialize(db, options = {})
    @db, @options = db, options
    @reqs = @db["requirements"].find({"_name" => @options[:name]}, {:sort => ["date", :desc]})
  end
  
  def exist?; @reqs.count > 0 end
  def name; @options[:name] end
  def dates; @reqs.map {|doc| doc["date"]} end

  def to_json(*args)
    @reqs.map {|doc|
      doc.delete("_id")
      doc["date"] = doc["date"].xmlschema(2)
      doc
    }.to_json
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
