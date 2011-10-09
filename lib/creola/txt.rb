require 'creola/core'

class CreolaTxt < Creola
  def creole_escape(text)
    if text.gsub!(%r((http|ftp)://[^\s]+), '~\&').nil?
      text.gsub!(%r([~/*\\{\[]+), '~\&')
    end
    text
  end
  
  def to_txt; render end
  def root(content); content.join end
  def line_break; "\\\\" end
  def heading(level, text); "=" * level << " " << text << " " << "=" * level << "\n" end
  def paragraph(*parts); parts.join << "\n\n" end
  def nowiki(text); "{{{\n" + text.sub(/\r?\n\z/, '') + "\n}}}\n" end
  def nowiki_inline(text); "{{{" + text + "}}}" end
  def bold(*parts); ["**"] + parts + ["**"] end
  def italic(*parts); ["//"] + parts + ["//"] end
  def unnumbered(*items); items.last << "\n"; items end
  def numbered(*items); items.last << "\n"; items end
  def unnumbered_item(level, *parts); "*" * level << " " << parts.join << "\n" end
  def numbered_item(level, *parts); "#" * level << " " << parts.join << "\n" end
  
  def link(url, text, namespace)
    str = "[[" << url
    str << "|" << text if text
    str << "]]"
  end
  
  def table(*rows); rows.last << "\n"; rows end
  def row(*cells); cells.join << "|\n" end
  def cell(*parts); "|" + parts.join end
  def header_cell(*parts); "|=" + parts.join end
  def image(url, text)
    str = "{{" << url
    str << "|" << text if text
    str << "}}"
  end
  def horizontal_rule; "----\n\n" end
  def words(*words) words.map {|w| creole_escape(w)} end; 
end
