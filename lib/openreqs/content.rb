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
    @requirements_table = @options[:peer] ? @db["requirements.#{@options[:peer]}"] : @db["requirements"]
    @docs_table = @options[:peer] ? @db["docs.#{@options[:peer]}"] : @db["docs"]
    @options[:date] ||= Time.now.utc + 1
    @doc = @options[:doc].clone if @options[:doc]

    @doc ||= @docs_table.find_one(
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
    
  def requirements
    if @requirements
      @requirements
    else
      all_reqs = @requirements_table.find(
        { "_name" => {"$in" => requirement_list},
          "date"=> {"$lt" => @options[:date]}
        }, {:sort => ["date", :desc]}
      ).to_a
      @requirements = requirement_list.map {|req_name|
        if req = all_reqs.find {|creq| creq["_name"] == req_name}
          Req.new(@db, nil, :req => req, :context => @options[:context])
        end
      }.compact
    end
  end
  
  def to_json(*args)
    doc = @doc.clone
    doc.delete("_id")
    doc["date"] = doc["date"].xmlschema(2)
    doc["_reqs"] = requirements
    doc.to_json
  end

  def to_link(*args)
    doc = @doc.clone
    doc.delete("_id")
    doc["date"] = doc["date"].xmlschema(2)
    doc["_reqs"] = requirements
    doc.to_link
  end
  
  def to_hash; @doc || {} end
  def to_html
    DocHTML.new(content,
      :docs => docs,
      :requirements => requirements,
      :context => @options[:context]
    ).to_html 
  end
  def to_txt; DocParserTxt.new(content, :name => name, :requirements => requirements).to_txt end
  def to_reqif
    DocParserReqIf.new(content, :name => name, :requirements => requirements).to_txt
  end
end

class DocVersions
  include Enumerable
  
  def initialize(db, options = {})
    @db, @options = db, options
    @docs_table = @options[:peer] ? @db["docs.#{@options[:peer]}"] : @db["docs"]
    find_options = {"_name" => @options[:name]}
    find_options["date"] = {"$gt" => @options[:after]} if @options[:after]
    @docs = @docs_table.find(find_options, {:sort => ["date", :desc]}).to_a
  end
  
  def empty?; @docs.empty? end
  def exist?; !empty? end

  def name; @options[:name] end
  def dates; @docs.map {|doc| doc["date"]} end

  def each
    @docs.each {|doc| yield Doc.new(@db, name, @options.merge(:doc => doc))}
    self
  end
  
  def to_json(*args)
    @docs.map {|doc|
      doc.delete("_id")
      doc["date"] = doc["date"].xmlschema(2)
      doc
    }.to_json
  end

  def to_link(*args)
    @docs.map {|doc|
      doc.delete("_id")
      doc["date"] = doc["date"].xmlschema(2)
      doc
    }.to_link
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
    elsif req = @options[:requirements].find {|creq| creq.name == uri}
      ReqHTML.new(req, :context => context).to_html
    elsif @options[:docs].include? uri
      super(context.to("/d/#{uri}"), text || uri, namespace)
    else
      super(context.to("/r/#{uri}/edit"), text || uri, namespace)
    end
  end
end

class DocIndexHTML < CreolaHTML
  def link(uri, text, namespace)
    context = @options[:context]
    
    if @options[:docs].include? uri
      super(context.to("/d/#{uri}"), text || uri, namespace)
    else
      super(context.to("/d/#{uri}/edit"), text || uri, namespace)
    end
  end
end

class DocParserReqIf < CreolaTxt
  attr_accessor :coreContent, :reqifHeader, :requirementsSection, :specificationSection, :reqIfOutput, :firstHeading, :previousLevel
  def initialize(content, options)
    @reqifHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<REQ-IF xmlns=\"http://www.omg.org/spec/ReqIF/20110401/reqif.xsd\"\n  xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n  xsi:schemaLocation=\"http://www.omg.org/spec/ReqIF/20110401/reqif.xsd http://www.omg.org/spec/ReqIF/20110401/reqif.xsd\"\n  xml:lang=\"en\">\n"
    @reqifHeader << "<THE-HEADER>\n"
    @reqifHeader << "<REQ-IF-HEADER IDENTIFIER=\"#{options[:name]}\">\n"
    @reqifHeader << "<COMMENT>No comments</COMMENT>\n"
    @reqifHeader << "<CREATION-TIME>" + Time.now.strftime("%Y-%m-%dT%H:%M:%S") + "</CREATION-TIME>\n"
    @reqifHeader << "<REPOSITORY-ID>Req-if file repository</REPOSITORY-ID>\n"
    @reqifHeader << "<REQ-IF-TOOL-ID>OpenReqs ReqIf exporter</REQ-IF-TOOL-ID>\n"
    @reqifHeader << "<REQ-IF-VERSION>1.0</REQ-IF-VERSION>\n"
    @reqifHeader << "<SOURCE-TOOL-ID>Openreqs</SOURCE-TOOL-ID>\n"
    @reqifHeader << "<TITLE>#{options[:name]}</TITLE>\n"
    @reqifHeader << "</REQ-IF-HEADER>\n"
    @reqifHeader << "</THE-HEADER>\n"
    @coreContent = "<CORE-CONTENT>\n"
    @coreContent << "<REQ-IF-CONTENT>\n"
    @requirementsSection = "<SPEC-OBJECTS>\n"
    @specificationSection = ""
    @reqIfOutput = ""
    @firstHeading = true
    @previousLevel = 0
    super(content, options)
  end
  def line_break; end
  def heading(level, text)
    if @firstHeading
      @specificationSection << "<SPECIFICATIONS>\n"
      @specificationSection << "<SPECIFICATION IDENTIFIER=\"#{@options[:name]}\">\n"
      @firstHeading = false
    else
      @specificationSection << "</SPEC-HIERARCHY>\n"
    end
    if (level > @previousLevel)
      @specificationSection << "<CHILDREN>\n" * (level-@previousLevel)
      @specificationSection << "<SPEC-HIERARCHY DESC=\"#{text}\">\n"
    elsif (level < @previousLevel)
      @specificationSection << "</CHILDREN>\n" * (@previousLevel-level)
      @specificationSection << "<SPEC-HIERARCHY DESC=\"#{text}\">\n"
    else
      @specificationSection << "<SPEC-HIERARCHY DESC=\"#{text}\">\n"
    end
    @previousLevel = level
  end
  def link(uri, text, namespace)
    if req = @options[:requirements].find {|creq| creq.name == uri}
      @requirementsSection << req.to_reqif
      @specificationSection << "<OBJECT>\n"
      @specificationSection << "<SPEC-OBJECT-REF>#{req.name}</SPEC-OBJECT-REF>\n"
      @specificationSection << "</OBJECT>\n"
    end
  end
  def root(content)
    @requirementsSection << "</SPEC-OBJECTS>\n"
    @specificationSection << "</SPEC-HIERARCHY>\n"
    @specificationSection << "</CHILDREN>\n" * (@previousLevel-0)
    @specificationSection << "</SPECIFICATION>\n"
    @specificationSection << "</SPECIFICATIONS>\n"
    @coreContent << @requirementsSection 
    @coreContent << @specificationSection
    @coreContent << "</REQ-IF-CONTENT>\n"
    @coreContent << "</CORE-CONTENT>\n"
    @reqIfOutput = @reqifHeader + @coreContent + "</REQ-IF>"
    @reqIfOutput
  end
  def to_txt; super end
end

class DocParserTxt < CreolaTxt
  def heading(level, text); super(level + 1, text) end
  
  def image(url, text)
    if url =~ %r{^(http|ftp)://}
      super(url, text)
    elsif req = @options[:requirements].find {|creq| creq.name == url}
      req.to_txt + "\n"
    else
      super(url, text)
    end
  end
  
  def to_txt; "= #{@options[:name]} =\n\n" + super end
end

class Req
  attr_reader :options
  def initialize(db, name, options = {})
    @db, @options = db, options
    @options[:date] ||= Time.now.utc + 1
    @req = @options[:req].clone if @options[:req]
    
    if @req.nil? 
      @requirements_table = @options[:peer] ? @db["requirements.#{@options[:peer]}"] : @db["requirements"]
      @req = @requirements_table.find_one(
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
  def []=(attr, value); @req[attr] = value end
  def date; self["date"] end
  def content; self["_content"] || '' end
  def name; self["_name"] end
  def to_hash; @req || {} end
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

  def to_reqif
    str = "<SPEC-OBJECT IDENTIFIER=\"#{name}\" LAST-CHANGE=\"#{date.strftime("%Y-%m-%dT%H:%M:%S")}\">\n"
    str << "<VALUES>\n"
    str << "<ATTRIBUTE-VALUE-STRING THE-VALUE=\"#{name}\">\n"
    str << "<DEFINITION>\n"
    str << "<ATTRIBUTE-DEFINITION-STRING-REF>ID</ATTRIBUTE-DEFINITION-STRING-REF>\n"
    str << "</DEFINITION>\n"
    str << "</ATTRIBUTE-VALUE-STRING>\n"
    str << "<ATTRIBUTE-VALUE-STRING THE-VALUE=\"#{content}\">\n"
    str << "<DEFINITION>\n"
    str << "<ATTRIBUTE-DEFINITION-STRING-REF>Description</ATTRIBUTE-DEFINITION-STRING-REF>\n"
    str << "</DEFINITION>\n"
    str << "</ATTRIBUTE-VALUE-STRING>\n"
    attributes.each {|k, v|
      str << "<ATTRIBUTE-VALUE-STRING THE-VALUE=\"#{v}\">\n"
      str << "<DEFINITION>\n"
      str << "<ATTRIBUTE-DEFINITION-STRING-REF>#{k}</ATTRIBUTE-DEFINITION-STRING-REF>\n"
      str << "</DEFINITION>\n"
      str << "</ATTRIBUTE-VALUE-STRING>\n"
    }
    str << "</VALUES>\n"
    str << "</SPEC-OBJECT>\n"
  end

  def to_link(linkName)
    if exist? then
      str = "#{name} "
      str << content
      puts "Looking for #{linkName}\n"
      unless @req[linkName].nil?
        @requirement_list ||= CreolaExtractURL.new(@req[linkName]).to_a
        @reqs = @requirement_list.map {|req_name| Req.new(mongo, req_name, :context => self) }
        @reqs.each {|req|
          puts req
          req.to_txt
        }
      end
      str << "\n"
      # puts str
    else
    end
  end

end

class ReqVersions
  include Enumerable

  def initialize(db, options = {})
    @db, @options = db, options
    @requirements_table = @options[:peer] ? @db["requirements.#{@options[:peer]}"] : @db["requirements"]
    find_options = {"_name" => @options[:name]}
    find_options["date"] = {"$gt" => @options[:after]} if @options[:after]
    @reqs = @requirements_table.find(find_options, {:sort => ["date", :desc]}).to_a
  end
  

  def empty?; @reqs.count == 0 end
  def exist?; !empty? end

  def name; @options[:name] end
  def dates; @reqs.map {|doc| doc["date"]} end

  def each
    @reqs.each {|req| yield Req.new(@db, name, @options.merge(:req => req))}
    self
  end
  
  def to_json(*args)
    @reqs.map {|doc|
      doc.delete("_id")
      doc["date"] = doc["date"].xmlschema(2)
      doc
    }.to_json
  end

  def to_link(*args)
    @reqs.map {|doc|
      doc.delete("_id")
      doc["date"] = doc["date"].xmlschema(2)
      doc
    }.to_link
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
