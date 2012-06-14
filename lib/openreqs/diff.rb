require 'forwardable'
require 'diff/lcs'
require 'creola/html'
require 'creola/txt'


class CreolaList < CreolaTxt
  def root(content); content.flatten end
  def to_a; render end
  undef_method :to_txt
end

class CreolaDiff < Creola
  extend Forwardable
  attr_reader :discard_state
  
  def initialize(old_creole, new_creole, slave_parser)
    @old_content = CreolaList.new(old_creole).to_a
    @new_content = CreolaList.new(new_creole).to_a
    @slave_parser = slave_parser
    
    slave_parser.diff_parser = self
    super(nil, nil)
  end
  
  def_delegators :@slave_parser, :root, :line_break, :heading, :paragraph,
      :nowiki, :nowiki_inline, :bold, :italic,
      :unnumbered, :numbered, :unnumbered_item, :numbered_item,
      :link, :table, :row, :cell, :header_cell, :image, :horizontal_rule, :words
  
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

  private
  def tokenize
    @state = State::Root.new(self)
    Diff::LCS.traverse_sequences(@old_content, @new_content, self)
    @state = @state.parse(:EOS, nil)
    root(@state.finish)
  end
end

class ContentDiffHTML < CreolaHTML
  attr_accessor :diff_parser
  
  def words(*words);
    case diff_parser.discard_state
    when :remove
      %{<span class="remove">} + words.join + "</span>"
    when :add
      %{<span class="add">} + words.join + "</span>"
    else
      words.join
    end
  end
end

class ContentDiffHTMLNoClass < CreolaHTML
  attr_accessor :diff_parser
  
  def words(*words);
    case diff_parser.discard_state
    when :remove
      %{<span style="background-color: #fdd; text-decoration: line-through;">} + words.join + "</span>"
    when :add
      %{<span style="background-color: #dfd;">} + words.join + "</span>"
    else
      words.join
    end
  end
end

class DocDiff < CreolaDiff
  attr_reader :doc_old, :doc_new
  def initialize(doc_old, doc_new, options = {})
    options[:slave_parser] ||= ContentDiffHTML.new
    super(doc_old.content, doc_new.content, options[:slave_parser])
    @doc_old, @doc_new, @options = doc_old, doc_new, options
  end
  
  def heading(level, text); super(level + 1, text) end
  
  def image(url, text)
    req_old = @doc_old.requirements.find {|creq| creq.name == url}
    req_new = @doc_new.requirements.find {|creq| creq.name == url}
    if req_old || req_new
      case @discard_state
      when :remove
        ReqDiff.new(req_old, EmptyReq.new, @options).to_html
      when :add
        ReqDiff.new(EmptyReq.new, req_new, @options).to_html
      else
        ReqDiff.new(req_old, req_new, @options).to_html
      end
    elsif url !~ %r(/)
      "{{" + url + (text ? "|" + text : "") + "}}"
    else
      super(url, text)
    end
  end
end

class ReqDiff
  TEMPLATE = 'req_inline.haml'
  def initialize(req_old, req_new, options = {})
    @req_old, @req_new, @options = req_old || EmptyReq.new, req_new || EmptyReq.new, options
    @context = @options[:context]
    @content = CreolaDiff.new(@req_old.content, @req_new.content, options[:slave_parser])
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
