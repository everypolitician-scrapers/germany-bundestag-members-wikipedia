#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'
require 'wikidata_ids_decorator'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

class MembersPage < Scraped::HTML
  decorator WikidataIdsDecorator::Links

  field :members do
    table.xpath('.//tr[td]').map do |tr|
      fragment tr => MemberRow
    end
  end

  private

  def table
    table = noko.xpath(".//table[.//th[contains(.,'Mitglied')]]")
    raise "Can't find unique table of Members" unless table.count == 1
    table.first
  end
end

class MemberRow < Scraped::HTML
  field :id do
    wikiname.downcase.tr(' ', '_')
  end

  field :name do
    tds[0].css('a').first.text.tidy
  end

  field :sort_name do
    [tds[0].css('@data-sort-value'), tds[0].css('span[style*="none"]')].map { |v| v.text.tidy }.find { |t| !t.empty? }
  end

  field :party do
    tds[2].text.tidy
  end

  field :constituency do
    tds[4].text.tidy rescue ''
  end

  field :area do
    tds[3].text.tidy
  end

  field :term do
    id
  end

  field :wikiname do
    tds[0].css('a/@title').first.text
  end

  field :wikidata do
    tds[0].css('a/@wikidata').first.text
  end

  field :source do
    url
  end

  field :notes do
    tds[6].text.tidy unless tds[6].nil?
  end

  field :start_date do
    return unless notes
    return unless matched = notes.downcase.match(/eingetreten.*?am #{DATE_RE}/) ||
                            notes.downcase.match(/nachgewählt am #{DATE_RE}/)
    sort_date || date_from(*matched.captures)
  end

  field :end_date do
    return death_date unless death_date.to_s.empty?
    return unless notes
    return unless matched = notes.downcase.match(/ausgeschieden.*?am #{DATE_RE}/)
    sort_date || date_from(*matched.captures)
  end

  field :death_date do
    return unless notes
    return unless matched = notes.downcase.match(/verstorben.*?am #{DATE_RE}/)
    sort_date || date_from(*matched.captures)
  end

  private

  DATE_RE = '(\d+)\.?\s+([^ ]+)\s+(\d+)'

  MONTHS = %w(_nil januar februar märz april mai juni juli august september oktober november dezember).freeze

  def tds
    noko.css('td')
  end

  def month(str)
    MONTHS.find_index(str) or raise "Unknown month #{str}"
  end

  def date_from(dd, mm, yy)
    '%02d-%02d-%02d' % [yy, month(mm.downcase), dd]
  end

  def sort_date
    sortkey = tds[6].css('span.sortkey') if notes
    Date.parse(sortkey.text).to_s rescue nil
  end

  # TODO: other notes
  # elsif matched = notes.downcase.match(/bis zum #{DATE_RE} .*/)
  # TODO: old_name = matched.captures.pop
  # elsif matched = notes.downcase.match(/#{DATE_RE} aus der fraktion (.*) ausgeschieden/)
  # TODO: left faktion
  # elsif matched = notes.downcase.match(/seit #{DATE_RE} fraktionslos/)
  # TODO: left faktion
  # elsif matched = notes.downcase.match(/ab #{DATE_RE} fraktionslos/) ||
  #   notes.downcase.match(/fraktionslos ab #{DATE_RE}/)
  # TODO: left faktion
  # elsif notes.include?('nahm sein Mandat nicht an') || notes.include?('Mandat nicht angenommen')
  # TODO: didn't accept mandate
end

def scrape_term(id, url)
  data = MembersPage.new(response: Scraped::Request.new(url: url).response).members.map do |mem|
    mem.to_h.merge(term: id)
  end
  # data.each { |m| puts m.reject { |_k, v| v.to_s.empty? }.sort_by { |k, _v| k }.to_h }
  ScraperWiki.save_sqlite(%i(id term), data)
end

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
(1..18).reverse_each do |id, url|
  puts id
  url = 'https://de.wikipedia.org/wiki/Liste_der_Mitglieder_des_Deutschen_Bundestages_(%d._Wahlperiode)' % id
  scrape_term(id, url)
end
