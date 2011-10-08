class Creola
  VERSION="1"
  TOKENS = [
    [/\A *\r?\n/, :EOL],
    [/\A *\z/, :EOL],
    [%r{\A~(http|ftp)://[^\s|\]]+[^\s|,.?!:;"'\]]}, :TILDE],
    [/\A~[^\s]/, :TILDE],
    [/\A=/, :EQUAL],
    [/\A\|/, :PIPE],
    [/\A:/, :COLON],
    [/\A----/, :HR],
    [/\A\*\*/, :DOUBLE_STAR],
    [/\A\*/, :STAR],
    [/\A\#/, :NUMBERED],
    [%r{\A\\\\}, :DOUBLE_SLASH],
    [%r{\A//}, :ITALIC],
    [/\A\[\[/, :BEGIN_LINK],
    [/\A\]\]/, :END_LINK],
    [/\A{{{(\r?\n)?/, :BEGIN_NOWIKI],
    [/\A}}}/, :END_NOWIKI],
    [/\A{{/, :BEGIN_IMAGE],
    [/\A}}/, :END_IMAGE],
    [%r{\A(http|ftp)://[^\s|\]]+[^\s|,.?!:;"'\]]}, :URL],
    [/\A\w+/, :OTHER],
    [/\A +/, :SPACE],
  ]
  DEFAULT_TOKEN = [[/\A./, :OTHER]]
  
  module State
    class BasicState
      attr_accessor :old_state, :state
      def initialize(context, old_state)
        @context = context
        @old_state, @state = old_state, self
        @result = []
      end
      
      def push(state)
        state = @context.states[state]
        find_current_state.state = state.new(@context, self)
      end
      
      def pop
        current_state = find_current_state
        next_state = current_state.state = current_state.old_state
        next_state.reduce(current_state)
        find_current_state
      end

      def parse(token, text)
        find_state = find_current_state
        method_name = "token_" + token.to_s
        method_name = "default_token" if !find_state.respond_to?(method_name)
        find_state.__send__(method_name, token, text)
        find_current_state
      end
      
      def reduce(current_state)
        @state = self
        method_name = "reduce_" + current_state.class.state_name
        __send__(method_name, current_state)
      end
      
      def find_current_state
        find_state = self
        find_state = find_state.state while find_state.state != find_state
        find_state
      end
      
      def self.state_name
        to_s.sub(/^.*::/, '').gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase
      end
    end
    
    module EndParagraph
      def blank_lines?; @blank_lines end
      def token_EOL(token, text); push(:eol) end
      def reduce_eol(reduced)
        @blank_lines = true; pop if reduced.blank_lines?
      end
    end
        
    class Root < BasicState
      def initialize(context)
        @context = context
        @old_state = @state = self
        @result = []
      end
      
      def finish; @result.compact end
      def token_EOL(token, text); end
      def token_EOS(token, text); end
      def token_SPACE(token, text); end
      def token_EQUAL(token, text); push(:heading_level).parse(token, text) end
      def token_STAR(token, text); push(:unnumbered).parse(token, text) end
      def token_NUMBERED(token, text); push(:numbered).parse(token, text) end
      def token_BEGIN_NOWIKI(token, text); push(:nowiki) end
      def token_PIPE(token, text); push(:table).parse(token, text) end
      def token_HR(token, text); push(:horizontal_rule) end
      def default_token(token, text); push(:paragraph).parse(token, text) end
      def reduce_default(reduced); @result << reduced.finish end
      %w(paragraph heading_level horizontal_rule numbered unnumbered nowiki table).each {|reduce|
        alias_method "reduce_#{reduce}", :reduce_default
      }
    end
    
    class InlineWord < BasicState
      attr_reader :finish
      def blank_lines?; @blank_lines end
      def token_TILDE(token, text); parse(:OTHER, text.sub(/^~/, '')) end
      def token_URL(token, text); @finish = @context.link(text, nil, nil); pop end
      def token_BEGIN_LINK(token, text); push(:link) end
      def token_BEGIN_IMAGE(token, text); push(:image) end
        
      def state_include?(checked_state)
        checked_state = checked_state.to_s
        state, found = self, false
        while state != state.old_state
          state = state.old_state
          found = true if checked_state == state.class.state_name
        end   
        found
      end
      
      def token_DOUBLE_STAR(token, text)
        state_include?(:multiline_bold) ? parse(:OTHER, "**") : push(:multiline_bold)
      end
      
      def token_ITALIC(token, text)
        state_include?(:multiline_italic) ? parse(:OTHER, "//") : push(:multiline_italic)
      end
      
      def token_BEGIN_NOWIKI(token, text); push(:nowiki_inline) end
      def token_DOUBLE_SLASH(token, text); @finish = @context.line_break; pop end
      def token_OTHER(token, text); push(:words).parse(token, text) end
      def default_token(token, text); parse(:OTHER, text) end
      %w(link image nowiki_inline words).each {|reduce|
        define_method("reduce_#{reduce}") do |reduced|
          @finish = reduced.finish
          pop
        end
      }
      %w(multiline_bold multiline_italic).each {|reduce|
        define_method("reduce_#{reduce}") do |reduced|
          @blank_lines = reduced.blank_lines?
          @finish = reduced.finish
          pop
        end
      }
    end
    
    class Words < BasicState
      def finish; @context.words(*@result) end
      def token_OTHER(token, text); @result << text end
      def token_SPACE(token, text); @result << text end
      def default_token(token, text); pop.parse(token, text) end
    end
    
    # {{{
    #   Nowiki Blocks
    # }}}
    class Nowiki < BasicState
      def finish; @context.nowiki(@text) end
      def initialize(*args); super; @text = '' end
      def token_EOS(token, text); pop.parse(token, text) end
      def token_END_NOWIKI(token, text); pop end
      def default_token(token, text); @text << text end
    end
    
    # {{{ No wiki inline }}}
    class NowikiInline < BasicState
      def finish; @context.nowiki_inline(@text) end
      def initialize(*args); super; @text = '' end
      def token_EOS(token, text); pop.parse(token, text) end
      def token_EOL(token, text); pop.parse(token, text) end
      def token_END_NOWIKI(token, text); pop end
      def default_token(token, text); @text << text end
    end
    
    # This a paragraph
    #
    # This is another one
    class Paragraph < BasicState
      include EndParagraph
      def finish; @context.paragraph(*@result) end
      def token_EOS(token, text); pop.parse(token, text) end
      def default_token(token, text); push(:inline_word).parse(token, text) end
      def reduce_inline_word(reduced)
        @result << reduced.finish
        @blank_lines = reduced.blank_lines?
        pop if blank_lines?
      end
    end
    
    # * Unnumbered item
    # ** Second level
    class Unnumbered < BasicState
      def finish; @context.unnumbered(*@result) end
      def token_DOUBLE_STAR(token, text); parse(:STAR, "*").parse(:STAR, "*") end
      def token_STAR(token, text); push(:unnumbered_item_level).parse(token, text) end
      def reduce_unnumbered_item_level(reduced); @result << reduced.finish end
      def default_token(token, text); pop.parse(token, text) end      
    end
    
    class UnnumberedItemLevel < BasicState
      def finish; @context.unnumbered_item(@level, *@item) end
      def initialize(*args); super; @level = 0 end
      def token_DOUBLE_STAR(token, text); parse(:STAR, "*").parse(:STAR, "*") end
      def token_STAR(token, text); @level += 1 end
      def default_token(token, text); push(:skip_space).parse(token, text) end
      def reduce_skip_space(reduced); @item = reduced.finish; pop end
    end
    
    # # Numbered item
    # ## Second level
    class Numbered < BasicState
      def finish; @context.numbered(*@result) end
      def token_NUMBERED(token, text); push(:numbered_item_level).parse(token, text) end
      def reduce_numbered_item_level(reduced); @result << reduced.finish end
      def default_token(token, text); pop.parse(token, text) end          
    end
    
    class NumberedItemLevel < BasicState
      def finish; @context.numbered_item(@level, *@item) end
      def initialize(*args); super; @level = 0 end
      def token_NUMBERED(token, text); @level += 1 end
      def default_token(token, text); push(:skip_space).parse(token, text) end
      def reduce_skip_space(reduced); @item = reduced.finish; pop end
    end
    
    class SkipSpace < BasicState
      def finish; @result end
      def token_SPACE(token, text); end
      def default_token(token, text); push(:item).parse(token, text) end
      def reduce_item(reduced); @result = reduced.finish; pop end
    end
   
    class Item < BasicState
      include EndParagraph
      def finish; @result end
      def token_EOS(token, text); pop.parse(token, text) end
      def default_token(token, text); push(:inline_word).parse(token, text) end
      def reduce_inline_word(reduced)
        @result << reduced.finish 
        @blank_lines = reduced.blank_lines?
        pop if blank_lines?
      end
    end
    
    # ----
    class HorizontalRule < BasicState
      def finish; @other ? nil : @context.horizontal_rule end
      def token_EOL(token, text); pop end
      def token_EOS(token, text); pop.parse(token, text)  end
      def default_token(token, text); @other = true; pop.parse(:OTHER, "----").parse(token, text) end
    end
    
    # = First level heading
    # == Second level heading ==
    class HeadingLevel < BasicState
      def finish; @context.heading(@level, @heading) end
      def initialize(*args); super; @level = 0 end
      def token_EQUAL(token, text); @level += 1 end
      def token_EOS(token, text); pop.parse(token, text)  end
      def default_token(token, text); push(:heading).parse(token, text) end
      def reduce_heading(reduced); @heading = reduced.finish; pop end
    end
    
    class Heading < BasicState
      def finish; @result.strip.sub(/ *=* *$/, '') end
      def initialize(*args); super; @result = '' end
      def token_EOL(token, text); pop end
      def token_EOS(token, text); pop.parse(token, text)  end
      def default_token(token, text); @result << text end
    end
    
    class Eol < BasicState
      def blank_lines?; @blank_lines end
      def token_SPACE(token, text); end
      %w(EQUAL NUMBERED STAR DOUBLE_STAR BEGIN_NOWIKI PIPE HR EOS).each {|t|
        define_method("token_#{t}") {|token, text| @blank_lines = true; pop.parse(token, text) }
      }
      
      def token_EOL(token, text); @blank_lines = true; push(:blank_lines) end
      def reduce_blank_lines(reduced); pop end
      def default_token(token, text); pop.parse(:SPACE, " ").parse(token, text) end
    end
    
    class BlankLines < BasicState
      def token_EOL(token, text); end
      def default_token(token, text); pop.parse(token, text) end
    end
    
    # {{myimage.png|this is my image}} 
    class Image < BasicState
      def finish; @context.image(@url, @text) end
      def initialize(*args); super; @url, @text = '', nil end
      def token_PIPE(token, text); push(:image_text) end
      def token_EOS(token, text); pop.parse(token, text) end
      def token_EOL(token, text); pop.parse(token, text) end
      def token_END_IMAGE(token, text); pop end
      def default_token(token, text); @url << text end
      def reduce_image_text(reduced); @text = reduced.finish end
    end
    
    class ImageText < BasicState
      def finish; @text end
      def initialize(*args); super; @text = '' end
      def token_EOS(token, text); pop.parse(token, text) end
      def token_EOL(token, text); pop.parse(token, text) end
      def token_END_IMAGE(token, text); pop.parse(token, text) end
      def default_token(token, text); @text << text end
    end

    class Multiline < BasicState
      include EndParagraph
      def token_EOS(token, text); pop.parse(token, text) end
      def default_token(token, text); push(:inline_word).parse(token, text) end
      def reduce_inline_word(reduced)
        @result << reduced.finish
        @blank_lines = reduced.blank_lines?
        pop if blank_lines?
      end      
    end
    
    # ** bold **
    class MultilineBold < Multiline
      def finish; @context.bold(*@result) end
      def token_DOUBLE_STAR(token, text); pop end
    end
    
    # // Italic //
    class MultilineItalic < Multiline
      def finish; @context.italic(*@result) end
      def token_ITALIC(token, text); pop end
    end

    # http://example.com
    # [[Internal Wiki|Link text]]
    # [[Wiki:InterWikiLink]]
    # [[http://example.com| Link text]]
    class Link < BasicState
      def finish; @context.link(@url, @text, @namespace) end
      def initialize(*args); super; @url, @text, @namespace = '', nil, nil end
      def token_COLON(token, text); @namespace, @url = @url, '' end
      def token_PIPE(token, text); push(:link_text) end
      def token_EOS(token, text); pop.parse(token, text) end
      def token_EOL(token, text); pop.parse(token, text) end
      def token_END_LINK(token, text); pop end
      def default_token(token, text); @url << text end
      def reduce_link_text(reduced); @text = reduced.finish end
    end
    
    class LinkText < BasicState
      def finish; @text end
      def initialize(*args); super; @text = '' end
      def token_EOS(token, text); pop.parse(token, text) end
      def token_EOL(token, text); pop.parse(token, text) end
      def token_END_LINK(token, text); pop.parse(token, text) end
      def default_token(token, text); @text << text end
    end
    
    # |=header col1|=header col2|
    # |col1|col2| 
    class Table < BasicState
      def finish; @context.table(*@result) end
      def token_PIPE(token, text); push(:row).parse(token, text) end
      def default_token(token, text); pop.parse(token, text) end
      def reduce_row(reduced); @result << reduced.finish end
    end
    
    class Row < BasicState
      def finish; @context.row(*@result) end
      def token_PIPE(token, text); push(:cell) end
      def default_token(token, text) pop.parse(token, text) end
      def reduce_cell(reduced)
        @result << reduced.finish if reduced.finish
        @blank_lines = reduced.blank_lines?
        pop if @blank_lines
      end
    end
    
    class Cell < Multiline
      def finish; !@result.empty? and @context.cell(*@result) end
      def token_EQUAL(token, text); @header_cell = true end
      def token_PIPE(token, text); pop.parse(token, text) end
    end

  end
  
  attr_reader :text, :options, :states
  def initialize(text = '', options = {})
    @text, @options = text, options
    @states = {}
    State.constants.each {|state|
      state = State.const_get(state)
      next if !state.is_a? Class
      @states[state.state_name.to_sym] = state
    }
  end
  
  def render; tokenize end
  
  def root(content); raise "You need to redefine this method" end
  def line_break; end
  def heading(level, text); end
  def paragraph(*parts); end
  def nowiki(text); end
  def nowiki_inline(text); end
  def bold(*parts); end
  def italic(*parts); end
  def numbered(*items);  end
  def unnumbered(*items); end
  def numbered_item(level, *parts);  end
  def unnumbered_item(level, *parts); end
  def link(url, text, namespace); end
  def table(*rows); end
  def row(*cells); end
  def cell(*parts); end
  def header_cell(*parts); end
  def image(url, text); end
  def horizontal_rule; end
  def words(*words); end
  
  private
  def tokenize
    state = State::Root.new(self)
    @text.each_line {|str| state = tokenize_string(str, state) }
    state = state.parse(:EOS, nil)
    
    root(state.finish)
  end
    
  def tokenize_string(str, state)
    token_patterns = TOKENS + DEFAULT_TOKEN
    while !str.empty?
      token = token_patterns.each {|pattern, t|
        break t if pattern.match(str)
      }
      
      text, str = $&, $'
      state = state.parse(token, text)
    end
    state
  end
  
end
