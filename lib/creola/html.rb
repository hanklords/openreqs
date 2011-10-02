require 'creola/core'

class CreolaHTML < Creola
  def to_html; render end
    
  private
  def root(content); content.join end
  def line_break; "<br />" end
  def heading(level, text); "<h#{level}>" + text + "</h#{level}>\n" end
  def paragraph(*parts); "<p>" + parts.join + "</p>\n" end
  def nowiki(text); "<pre>" + text + "</pre>\n" end
  def nowiki_inline(text); text end
  def bold(*parts); "<strong>" + parts.join + "</strong>" end
  def italic(*parts); "<em>" + parts.join + "</em>" end
    
  def make_list(list_str, *items)
    str = ""
    current_level = root = items.first[0] - 1
    items.each {|level, item|
      if level > current_level
        str << "<#{list_str}>\n" * (level - current_level)
      elsif
        level < current_level
        str << "</li>\n</#{list_str}>" * (current_level - level)
      elsif level == current_level
        str << "</li>\n"
      end
      
      current_level = level
      str << "<li>" << item
    }
    str << "</li>\n</#{list_str}>" * (current_level - root)
    str << "\n"
  end

  def unnumbered(*items) make_list("ul", *items) end
  def numbered(*items); make_list("ol", *items) end
  def unnumbered_item(level, *parts); [level, parts.join] end
  def numbered_item(level, *parts); [level, parts.join] end
  
  def link(url, text, namespace); %{<a href="#{url}">#{text || url}</a>} end
  def table(*rows); "<table>\n" + rows.join + "</table>\n" end
  def row(*cells); "<tr>" + cells.join + "</tr>\n" end
  def cell(*parts); "<td>" + parts.join + "</td>" end
  def header_cell(*parts); "<th>" + parts.join + "</th>" end
  def image(url, text); %{<img src="#{url}" alt="#{text || url}" />} end
  def horizontal_rule; "<hr />\n" end
end
