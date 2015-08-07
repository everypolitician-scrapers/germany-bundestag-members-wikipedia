#!/bin/env ruby
# encoding: utf-8

require 'colorize'
require 'mediawiki_api'
require 'nokogiri'
require 'open-uri'
require 'scraperwiki'

require 'pry'
require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def month(str)
  ['','januar','februar','märz','april','mai','juni','juli','august','september','oktober','november','dezember'].find_index(str) or raise "Unknown month #{str}".magenta
end

def date_from(dd, mm, yy)
  "%02d-%02d-%02d" % [yy, month(mm.downcase), dd]
end

def scrape_term(id, url)
  noko = noko_for(url)
  table = noko.xpath(".//table[.//th[contains(.,'Mitglied')]]")
  raise "Can't find unique table of Members" unless table.count == 1
  table.xpath('.//tr[td]').each do |tr|
    tds = tr.css('td')
    constituency = tds[4].text.tidy rescue ''
    wikiname = tds[0].css('a/@title').first.text
    data = { 
      id: wikiname.downcase.tr(' ', '_'),
      name: tds[0].css('a').first.text.tidy,
      sort_name: tds[0].css('span[style*="none"]').text,
      party: tds[2].text.tidy,
      constituency: constituency,
      area: tds[3].text.tidy,
      term: id,
      identifier__wikipedia_de: wikiname,
      source: url,
    }

    unless (tds[6].nil?) || (notes = tds[6].text.tidy).empty?
      data[:notes] = notes
      if sort_date = tds[6].css('span.sortkey')
        sort_date = Date.parse(sort_date.text).to_s rescue nil
      end
      date_re = '(\d+)\.?\s+([^ ]+)\s+(\d+)'
      if matched = notes.downcase.match(/ausgeschieden.*?am #{date_re}/)
        data[:end_date] = sort_date || date_from(*matched.captures)
      elsif matched = notes.downcase.match(/eingetreten.*?am #{date_re}/) || notes.downcase.match(/nachgewählt am #{date_re}/)
        data[:start_date] = sort_date || date_from(*matched.captures)
      elsif matched = notes.downcase.match(/verstorben.*?am #{date_re}/)
        data[:death_date] = data[:end_date] = sort_date || date_from(*matched.captures)
      elsif matched = notes.downcase.match(/bis zum #{date_re} .*/)
        old_name = matched.captures.pop # TODO
      elsif matched = notes.downcase.match(/#{date_re} aus der fraktion (.*) ausgeschieden/)
        # TODO left faktion
      elsif matched = notes.downcase.match(/seit #{date_re} fraktionslos/)
        # TODO left faktion
      elsif matched = notes.downcase.match(/ab #{date_re} fraktionslos/) || notes.downcase.match(/fraktionslos ab #{date_re}/)
        # TODO left faktion
      elsif notes.include?('nahm sein Mandat nicht an') || notes.include?('Mandat nicht angenommen')
        # TODO: didn't accept mandate
      else
        # warn "#{notes}".yellow
        # binding.pry
      end
    end
    # puts data
    ScraperWiki.save_sqlite([:id, :term], data)
  end
end

(1..18).reverse_each do |id, url|
  puts id
  # url = 'https://de.wikipedia.org/w/index.php?title=Liste_der_Mitglieder_des_Deutschen_Bundestages_(%d._Wahlperiode)&stable=0' % id
  url = 'https://de.wikipedia.org/wiki/Liste_der_Mitglieder_des_Deutschen_Bundestages_(%d._Wahlperiode)' % id
  scrape_term(id, url)
end
