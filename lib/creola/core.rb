class Creola
  VERSION="1"
  
  attr_reader :text
  def initialize(text, options = {}); @text, @options = text, options end
  def render; tokenize end
  
  private
  def tokenize
    str, token, state, result = @text, nil, [:root], [[]]
    
    while token != :EOS
      token = case str
      when /\A *\z/
        :EOS
      when /\A *\r?\n/
        :EOL
      when %r{\A~(http|ftp)://[^ |\]]+[^ |,.?!:;"'\]]}
        :TILDE
      when /\A~[^\s]/
        :TILDE
      when /\A=+/
        :EQUAL
      when /\A\|/
        :PIPE
      when /\A:/
        :COLON
      when /\A----/
        :HR
      when /\A\*\*/
        :DOUBLE_STAR
      when /\A\*/
        :STAR
      when /\A\#/
        :NUMBERED
      when %r{\A\\\\}
        :DOUBLE_SLASH
      when %r{\A\//}
        :ITALIC
      when /\A\[\[/
        :BEGIN_LINK
      when /\A\]\]/
        :END_LINK
      when /\A{{{/
        :BEGIN_NOWIKI
      when /\A}}}/
        :END_NOWIKI
       when /\A{{/
        :BEGIN_IMAGE
      when /\A}}/
        :END_IMAGE
      when %r{\A(http|ftp)://[^ |\]]+[^ |,.?!:;"'\]]}
        :URL
      when /\A\w+/
        :OTHER
      when /\A +/
        :SPACE
      else
        str =~ /\A./
        :OTHER
      end
      
      text, str = $&, $'
      parse(token, text, state, result)
    end
    
    root(result[0])
  end
  
  def parse(token, text, state, result)
    case state.last
    when :root
      case token
      when :EOL, :EOS, :SPACE
      when :EQUAL
        state.push :heading
        result.push [text.length, '']
      when :STAR
        state.push :unnumbered
        result.push []
        parse(token, text, state, result)
      when :NUMBERED
        state.push :numbered
        result.push []
        parse(token, text, state, result)
      when :BEGIN_NOWIKI
        state.push :nowiki
        result.push ''
      when :PIPE
        state.push :table
        result.push []
        parse(token, text, state, result)
      when :HR
        state.push :horizontal_rule
      when :block
        result.last << text
      else
        state.push :paragraph
        result.push []
        parse(token, text, state, result)
      end
    when :inline_word
      case token
      when :TILDE
        state.pop
        parse(:OTHER, text.sub(/^~/, ''), state, result)
      when :URL
        state.pop
        parse(:inline_word, link(text, nil, nil), state, result)
      when :BEGIN_LINK
        state.push :link
        result.push ['', nil, nil]
      when :BEGIN_IMAGE
        state.push :image
        result.push ['', nil]
      when :DOUBLE_STAR
        if state.include? :multiline_bold
          parse(:OTHER, "**", state, result)
        else
          state.push :multiline_bold
          result.push []
        end
      when :ITALIC
        if state.include? :multiline_italic
          parse(:OTHER, "//", state, result)
        else
          state.push :multiline_italic
          result.push []
        end
      when :BEGIN_NOWIKI
        state.push :nowiki_inline
        result.push ''
      when :DOUBLE_SLASH
        state.pop
        parse(:inline_word, line_break(), state, result)
      when :OTHER, :link, :multiline_italic, :multiline_bold, :nowiki_inline, :image
        state.pop 
        parse(:inline_word, text, state, result)
      else
        parse(:OTHER, text.to_s, state, result)
      end
      
    # {{{
    #   Nowiki Blocks
    # }}}
    when :nowiki
      case token
      when :END_NOWIKI
        state.pop
        text = result.pop
        parse(:block, nowiki(text), state, result)
      else
        result.last << text
      end
      
    # {{{ No wiki inline }}}
    when :nowiki_inline
      case token
      when :END_NOWIKI
        state.pop
        text = result.pop
        parse(:nowiki_inline, nowiki_inline(text), state, result)
      else
        result.last << text
      end
      
    # This a paragraph
    #
    # This is anothe one
    when :paragraph
      case token
      when :EOL
        state.push :eol
      when :inline_word
        result.last << text
      when :blank_lines, :EOS
        state.pop
        text = result.pop
        parse(:block, paragraph(*text), state, result)
      else
        state.push :inline_word
        parse(token, text, state, result)
      end
      
    # * Unnumbered item
    # ** Second level
    #
    # # Numbered item
    # ## Second level
    when :unnumbered, :numbered
      case token
      when :DOUBLE_STAR
        parse(:STAR, "*", state, result)
        parse(:STAR, "*", state, result)
      when :STAR, :NUMBERED
        if token == :NUMBERED
          state.push :numbered_item_level
        else
          state.push :unnumbered_item_level
        end
        result.push 0
        parse(token, text, state, result)
      when :item
        result.last << text
      else
        items = result.pop
        if state.last == :numbered
          content = numbered(*items)
        else
          content = unnumbered(*items)
        end
        state.pop
        
        parse(:block, content, state, result)
        parse(token, text, state, result)
      end
    when :unnumbered_item_level, :numbered_item_level
      case token
      when :DOUBLE_STAR
        parse(:STAR, "*", state, result)
        parse(:STAR, "*", state, result)
      when :STAR, :NUMBERED
        result[-1] += 1
      when :item
        level = result.pop
        if state.last == :numbered_item_level
          state.pop
          text = numbered_item(level, *text)
        else
          state.pop
          text = unnumbered_item(level, *text)
        end
        parse(token, text, state, result)
      else
        state.push :item
        result.push []
      end
    when :item
      case token
      when :EOL
        state.push :eol
      when :blank_lines, :EOS
        state.pop
        parts = result.pop
        parse(:item, parts, state, result)
        parse(token, nil, state, result) if token == :EOS
      when :inline_word
        result.last << text
      else
        state.push :inline_word
        parse(token, text, state, result)
      end
      
    # ----
    when :horizontal_rule
      case token
      when :EOL, :EOS
        state.pop
        parse(:block, horizontal_rule(), state, result)
      else
        state.pop
        parse(:OTHER, "----", state, result)
        parse(token, text, state, result)
      end
      
    # = First level heading
    # == Second level heading ==
    when :heading
      case token
      when :EOL, :EOS
        state.pop
        level, text = result.pop
        text = text.strip.sub(/ *=* *$/, '')
        parse(:block, heading(level, text), state, result)
      else
        result[-1].last << text
      end
    
    when :eol
      case token
      when :SPACE
      when :EQUAL, :NUMBERED, :STAR, :DOUBLE_STAR, :BEGIN_NOWIKI, :PIPE, :HR
        state.pop
        parse(:blank_lines, nil, state, result)
        parse(token, text, state, result)
      when :EOL
        state.push :blank_lines
      when :blank_lines, :EOS
        state.pop
        parse(:blank_lines, nil, state, result)
      else
        state.pop
        parse(:SPACE, " ", state, result)
        parse(token, text, state, result)
      end
    when :blank_lines
      case token
      when :EOL
      else
        state.pop
        parse(:blank_lines, nil, state, result)
        parse(:EOL, nil, state, result)
        parse(token, text, state, result)
      end
      
    # {{myimage.png|this is my image}} 
    when :image
      case token
      when :PIPE
        state.push :image_text
        result.last[1] = ''
      when :END_IMAGE
        state.pop
        text = result.pop
        parse(:image, image(*text), state, result)
      else
        result.last[0] << text
      end
    when :image_text
      case token
      when :END_IMAGE
        state.pop
        parse(token, text, state, result)
      else
        result.last[1] << text
      end
      
    # ** bold **
    when :multiline_bold
      case token
      when :EOL
        state.push :eol
      when :DOUBLE_STAR, :blank_lines, :EOS
        state.pop
        parts = result.pop
        parse(:multiline_bold, bold(*parts), state, result)
        parse(token, nil, state, result) if token == :blank_lines || token == :EOS
      when :inline_word
        result.last << text
      else
        state.push :inline_word
        parse(token, text, state, result)
      end

    # // Italic //
    when :multiline_italic
      case token
      when :EOL
        state.push :eol
      when :ITALIC, :blank_lines, :EOS
        state.pop
        parts = result.pop
        parse(:multiline_italic, italic(*parts), state, result)
        parse(token, nil, state, result) if token == :blank_lines || token == :EOS
      when :inline_word
        result.last << text
      else
        state.push :inline_word
        parse(token, text, state, result)
      end
      
    # http://example.com
    # [[Internal Wiki|Link text]]
    # [[Wiki:InterWikiLink]]
    # [[http://example.com| Link text]]
    when :link
      case token
      when :COLON
        result.last[2] = result.last[0]
        result.last[0] = ''
      when :PIPE
        state.push :link_text
        result.last[1] = ''
      when :END_LINK
        state.pop
        text = result.pop
        parse(:link, link(*text), state, result)
      else
        result.last[0] << text
      end
    when :link_text
      case token
      when :END_LINK
        state.pop
        parse(token, text, state, result)
      else
        result.last[1] << text
      end
      
    # |=header col1|=header col2|
    # |col1|col2| 
    when :table
      case token
      when :PIPE
        state.push :row
        result.push []
        parse(token, text, state, result)
      when :row
        result.last << text
      else
        state.pop
        rows = result.pop
        parse(:block, table(*rows), state, result)
        parse(token, text, state, result)
      end
    when :row
      case token
      when :PIPE
        state.push :cell
        result.push []
      when :cell
        result.last << text
      else
        state.pop
        cells = result.pop
        parse(:row, row(*cells), state, result)
      end
    when :cell, :header_cell
      case token
      when :EQUAL
        state[-1] = :header_cell
      when :EOL
        state.push :eol
      when :PIPE, :blank_lines, :EOS
        parts = result.pop
        if state.last == :header_cell
          cell_text = header_cell(*parts)
        else
          cell_text = cell(*parts)
        end
        state.pop

        parse(:cell, cell_text, state, result) if !parts.empty?
        parse(token, text, state, result)
      when :inline_word
        result.last << text
      else
        state.push :inline_word
        parse(token, text, state, result)
      end
    end
  end
  
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
end
