require 'creola/core'
require 'json'

class CreolaJSON < Creola
  def to_json; render end
    
  private
  def root(content); content.to_json end
  def line_break; {:line_break => true} end
  def heading(level, text); { :heading => {:level => level, :text => text}} end
  def paragraph(*parts); {:paragraph => {:content => merge_text(parts)}} end
  def nowiki(text); {:nowiki => {:inline => false, :content => text}} end
  def nowiki_inline(text); {:nowiki => {:inline => true, :content => text}} end
  def bold(*parts); {:bold => {:content => merge_text(parts)}} end
  def italic(*parts); {:italic => {:content => merge_text(parts)}} end
  def numbered(*items); {:numbered => {:content => items}} end
  def unnumbered(*items); {:unnumbered => {:content => items}} end
  def numbered_item(level, *parts); {:item => {:level => level, :content => merge_text(parts)}}  end
  def unnumbered_item(level, *parts); {:item => {:level => level, :content => merge_text(parts)}} end
  def link(url, text, namespace); {:link => {:url => url, :text => text , :namespace => namespace}} end
  def table(*rows); {:table => {:content => rows}} end
  def row(*cells); {:row => {:content => merge_text(cells)}} end
  def cell(*parts);  {:cell => {:header => false, :content => merge_text(parts)}} end
  def header_cell(*parts); {:cell => {:header => true, :content => merge_text(parts)}} end
  def image(url, text); {:image => {:url => url, :text => text}} end
  def horizontal_rule; {:horizontal_rule => true} end
  def merge_text(parts)
    parts.inject([]) {|m, part|
       if String === m.last and String === part
        m.last << part
      else
        m << part
      end
      m
    }
  end
end
