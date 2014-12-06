# -*- coding: utf-8 -*-
require 'nokogiri'
require 'restclient'
require 'csv'

# USAGE
#
#   $ gem install restclient nokogiri
#   $ ruby scrape-regjeringen-personregister.rb > personregister.csv

# forkortelser
# http://www.regjeringen.no/nb/om_regjeringen/tidligere/oversikt/del-iii---alfabetisk-personregister/forkortelser.html?id=418301

class Scraper
  def initialize
    @data     = []
    @resource = RestClient::Resource.new("http://www.regjeringen.no/")
  end

  def result
    index.each { |letter| fetch(letter) }
    @data
  end

  private

  def index
    doc = get('/nb/om_regjeringen/tidligere/oversikt/del-iii---alfabetisk-personregister.html?id=0')
    letters = ('A'..'Z').to_a + %w[Æ Ø Å]

    letters.map do |letter|
      node = doc.css("a[title=#{letter}]").first

      if node
        node['href']
      end
    end.compact
  end

  def fetch(url)
    doc = get(url)

    doc.css('.documentBody p').each do |par|
      text = par.text

      if text =~ /^(.+?), (.+?) \((\d+-\d*?)\)(.+?)$/
        positions          = $4.strip
        person             = {
          :last_name => $1.strip,
          :first_name => $2.strip,
          :years_lived => $3.strip,
          :source => text
        }

        person[:positions] = positions.split(/\s*,\s*/).map { |e| parse_position(e) }

        @data << person
      else
        @data << {:error => text}
      end
    end
  end

  def parse_position(str)
    case str
    when /(.+?) ([A-Z].*?)\s*(\d{4}.*?)?$/
      {
        :type       => $1.strip,
        :department => $2.strip,
        :years      => ($3.strip if $3)
      }
    when /(.+?) (\d{4}.*?)/
      {
        :type => $1,
        :department => nil,
        :years => $2.strip
      }
    else
      { :error => str }
    end
  end

  def get(path)
    Nokogiri::HTML.parse @resource[path].get
  end
end

if __FILE__ == $0
  RestClient.log = STDERR

  str = CSV.generate do |csv|
    csv << %w[pid last_name first_name years_lived position_type position_department position_years source]

    id = 0
    Scraper.new.result.each do |person|
      id += 1

      if person[:error]
        csv << [id, :error, nil, nil, nil, nil, nil, person[:error], nil]
      else
        row = person.values_at(:last_name, :first_name, :years_lived)
        row.unshift id

        person[:positions].each do |pos|
          if pos[:error]
            csv << row + [:error, nil, nil, person[:source]]
          else
            csv << row + [pos[:type], pos[:department], pos[:years], person[:source]]
          end
        end
      end
    end
  end

  puts str
end
