require 'diff/lcs'
require 'creola/html'
require 'creola/txt'

class CreolaList < CreolaTxt
  def root(content); content.flatten end
  def to_a; render end
  undef_method :to_txt
end

class ContentDiff < CreolaHTML
  def initialize(old_creole, new_creole, options = {})
    @old_content = CreolaList.new(old_creole).to_a
    @new_content = CreolaList.new(new_creole).to_a
    super(nil, options)
  end
  
  def match(event)
    @discard_state = nil
    @state = tokenize_string(event.new_element, @state)
  end

  def discard_a(event)
    @discard_state = :remove
    @state = tokenize_string(event.old_element, @state)
  end

  def discard_b(event)
    @discard_state = :add
    @state = tokenize_string(event.new_element, @state)
  end
  
  def words(*words);
    case @discard_state
    when :remove
      %{<span class="remove">} + words.join + "</span>"
    when :add
      %{<span class="add">} + words.join + "</span>"
    else
      words.join
    end
  end;
  
  private
  def tokenize
    @state = State::Root.new(self)
    Diff::LCS.traverse_sequences(@old_content, @new_content, self)
    @state = @state.parse(:EOS, nil)
    root(@state.finish)
  end
end

class DocDiff < ContentDiff
  def initialize(doc_old, doc_new, options = {})
    @doc_old, @doc_new = doc_old, doc_new
    super(@doc_old.content, @doc_new.content, options)
  end
  
  def heading(level, text); super(level + 1, text) end
  def link(uri, text, namespace)
    req_old = @doc_old.requirements[uri]
    req_new = @doc_new.requirements[uri]
    if req_old || req_new
      case @discard_state
      when :remove
        ReqDiff.new(req_old, EmptyReq.new, @options).to_html
      when :add
        ReqDiff.new(EmptyReq.new, req_new, @options).to_html
      else
        ReqDiff.new(req_old, req_new, @options).to_html
      end
    elsif @doc_old.docs.include?(uri) || @doc_new.docs.include?(uri)
      super(@options[:context].to("/d/#{uri}"), text || uri, namespace)
    else
      super(uri, text, namespace)
    end
  end
  
end

class ReqDiff
  TEMPLATE = 'req_inline.haml'
  def initialize(req_old, req_new, options = {})
    @req_old, @req_new, @options = req_old || EmptyReq.new, req_new || EmptyReq.new, options
    @context = @options[:context]
    @content = ContentDiff.new(@req_old.content, @req_new.content)
  end

  def attributes
    @attributes ||= Hash[@req_new.attributes.map {|k,v| [k, CreolaHTML.new(v)]}]
  end
  
  attr_reader :content
  def name; @req_new.name || @req_old.name end
  def date; @req_new.date || @req_old.date end
        
  def to_html
    template = File.join(@context.settings.views, TEMPLATE)
    engine = Haml::Engine.new(File.read(template))
    @context.instance_variable_set :@reqp, self
    engine.render(@context)
  end
end
