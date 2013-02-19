#!/usr/bin/env ruby
# encoding: UTF-8

require 'json'
require 'time'

VOTE_DATA_FILE   = File.open('rawdata/scraperwiki/scraped_unanimous_votes_154.csv')
KART_SAK_ID_FILE = File.open('rawdata/saksid/Dagsorden 20009-2010-tabseparated.txt')
PROP_DATA_FILE   = File.open('rawdata/forslag-vedtak-2009-2011/propositions-2009-2010.json')
VEDTAK_DATA_FILE = File.open('rawdata/forslag-vedtak-2009-2011/vedtak2009.json')

PROP_DATA        = Hash.new(Array.new).merge JSON.parse PROP_DATA_FILE.read
VEDTAK_DATA      = Hash.new(Array.new).merge JSON.parse VEDTAK_DATA_FILE.read

ISSUE_MAP = KART_SAK_ID_FILE.lines.reduce({}) do |issue_map, line|
        date, kart_nr, issue_id, sakskart_nr, short_text = line.split("\t").map(&:strip)
        issue_map[[kart_nr, sakskart_nr, date]] ||= []
        issue_map[[kart_nr, sakskart_nr, date]] << issue_id
        issue_map
      end

VOTES = VOTE_DATA_FILE.lines.reduce([]) do |votes, line|
  (date,index,daynr,casenum,msg) = line.split(",").map(&:strip)

  time        = Time.parse(date) + 12 * 60 * 60 # noon
  unique_time = time + Integer(daynr) * 60 + Integer(casenum)

  votes << {
    kind:            'hdo#vote',
    externalId:      "#{unique_time.to_i}e",
    externalIssueId: ISSUE_MAP[[daynr, casenum, time.strftime('%Y%m%d')]].join(",") || "",
    counts:          {
      for:     0,
      against: 0,
      absent:  0
      },
    personal:        false,
    enacted:         true,
    subject:         "Kart:#{daynr}, Sak:#{casenum}",
    time:            unique_time.iso8601,
    propositions:    PROP_DATA["#{date}:#{daynr}:#{casenum}"] + VEDTAK_DATA["#{daynr}:#{casenum}"]
  }
  votes
end

puts JSON.pretty_generate VOTES
# puts JSON.pretty_generate PROP_DATA

## TODO ##
# create hdo#vote objects
# From the SKxSy. -files, get the dagens reps. Create some map from the names to initials, perhaps using elastic search