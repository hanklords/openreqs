require 'json'
require 'creola/html'
require 'creola/txt'

class CreolaExtractURL < Creola
  def initialize(*args);  super; @links = [] end
  alias :to_a :render
  def root(content); @links end
  def link(url, text, namespace); @links << url end
end

class CreolaExtractInline < Creola
  def initialize(*args);  super; @links = [] end
  alias :to_a :render
  def root(content); @links end
  def image(url, text); @links << url end
end

class Doc
  attr_reader :options
  def initialize(db, name, options = {})
    @db, @name, @options = db, name, options
    #@requirements_table = @options[:peer] ? @db["requirements.#{@options[:peer]}"] : @db["requirements"]
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
  def []=(attr, value); @doc[attr] = value end
  def date; self["date"] end
  def content; self["_content"] || '' end
  def name; self["_name"] end
  def attributes
    exist? ? @doc.select {|k,v| k !~ /^_/ && k != "date" } : []
  end
  
  def docs; @all_docs ||= @db["docs"].find({}, {:fields => "_name"}).map {|doc| doc["_name"]}.uniq end
 
  def requirement_list
    @requirement_list ||= CreolaExtractInline.new(content).to_a
  end
    
  def requirements
    if @requirements
      @requirements
    else
      all_reqs = @docs_table.find(
        { "_name" => {"$in" => requirement_list},
          "date"=> {"$lt" => @options[:date]}
        }, {:sort => ["date", :desc]}
      ).to_a
      @requirements = requirement_list.map {|req_name|
        if req = all_reqs.find {|creq| creq["_name"] == req_name}
          Doc.new(@db, nil, :doc => req, :context => @options[:context])
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
    DocHTML.new(self,
      :docs => docs,
      :requirements => requirements,
      :template => @options[:context].settings.doc_template,
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
end

class ContentHTML < CreolaHTML
  def context; @options[:context] end
  
  def heading(level, text); super(level + 1, text) end
  def link(uri, text, namespace)
    if uri =~ %r{^(http|ftp)://}
      super(uri, text, namespace)
    elsif @options[:docs].include? uri
      super(context.to("/#{uri}"), text || uri, namespace)
    else
      super(context.to("/#{uri}/edit"), text || uri, namespace)
    end
  end
  
  def image(url, text)
    if url =~ %r{^(http|ftp)://}
      super(url, text)
    elsif req = @options[:requirements].find {|creq| creq.name == url}
      DocHTML.new(req, @options.merge(:template => context.settings.req_inline_template)).to_html
    elsif url !~ %r(/)
      req = Doc.new(context.settings.mongo, nil, @options.merge(:doc => {"_name" => url}))
      DocHTML.new(req, @options.merge(:template => context.settings.req_inline_template)).to_html
    else
      super(url, text)
    end
  end
end

class DocHTML
  def initialize(doc, options = {})
    @doc, @options = doc, options
    @context = @options[:context]
    @template = @options[:template]
  end
  
  def attributes
    @attributes ||= Hash[@doc.attributes.map {|k,v| [k, ContentHTML.new(v, @options)]}]
  end
  
  def name; @doc.name end
  def date; @doc.date end
  def content; ContentHTML.new(@doc.content, @options) end
    
  def to_html
    engine = Haml::Engine.new(@template)
    @context.instance_variable_set :@inline, self
    engine.render(@context)
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
      @requirementsSection = "<SPEC-OBJECT IDENTIFIER=\"#{req.name}\" LAST-CHANGE=\"#{req.date.strftime("%Y-%m-%dT%H:%M:%S")}\">\n"
      @requirementsSection << "<VALUES>\n"
      @requirementsSection << "<ATTRIBUTE-VALUE-STRING THE-VALUE=\"#{req.name}\">\n"
      @requirementsSection << "<DEFINITION>\n"
      @requirementsSection << "<ATTRIBUTE-DEFINITION-STRING-REF>ID</ATTRIBUTE-DEFINITION-STRING-REF>\n"
      @requirementsSection << "</DEFINITION>\n"
      @requirementsSection << "</ATTRIBUTE-VALUE-STRING>\n"
      @requirementsSection << "<ATTRIBUTE-VALUE-STRING THE-VALUE=\"#{req.content}\">\n"
      @requirementsSection << "<DEFINITION>\n"
      @requirementsSection << "<ATTRIBUTE-DEFINITION-STRING-REF>Description</ATTRIBUTE-DEFINITION-STRING-REF>\n"
      @requirementsSection << "</DEFINITION>\n"
      @requirementsSection << "</ATTRIBUTE-VALUE-STRING>\n"
      req.attributes.each {|k, v|
        @requirementsSection << "<ATTRIBUTE-VALUE-STRING THE-VALUE=\"#{v}\">\n"
        @requirementsSection << "<DEFINITION>\n"
        @requirementsSection << "<ATTRIBUTE-DEFINITION-STRING-REF>#{k}</ATTRIBUTE-DEFINITION-STRING-REF>\n"
        @requirementsSection << "</DEFINITION>\n"
        @requirementsSection << "</ATTRIBUTE-VALUE-STRING>\n"
      }
      @requirementsSection << "</VALUES>\n"
      @requirementsSection << "</SPEC-OBJECT>\n"
      
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
      str = "==== #{req.name} ====\n\n"
      str << req.content << "\n\n"
      str << "* date: #{req.date}\n"
      req.attributes.each {|k, v|
        str << "* #{k}: #{v}\n"
      }
      str << "\n\n"
    else
      super(url, text)
    end
  end
  
  def to_txt; "= #{@options[:name]} =\n\n" + super end
end
