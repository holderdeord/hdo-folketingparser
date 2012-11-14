#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'json'
require 'time'


class KartIssueMapper
  def initialize(filename)
    @file = File.new(filename)
  end

  def issue_map
    unless @issue_map
      @issue_map = {}
      @file.lines.each do |line|
        date, kart_nr, issue_id, sakskart_nr, short_text = line.split("\t").map(&:strip)
        @issue_map[[kart_nr, sakskart_nr]] = issue_id
      end
    end
    @issue_map
  end
end


class VoteParser
  def initialize(filename, issue_map)
    @file = File.new(filename)
    @file.set_encoding "iso-8859-1:utf-8"
    @issue_map = issue_map
  end

  def votes
    unless @votes
      @votes = {}
      @file.lines.each do |line|
        (date, kart_nr, sakskart_nr, vote_time, subject, option_description,
         result_code, count_for, count_against, name, repr_nr, person_id, 
         party, district_code, vote, option) = line.split(";").map(&:strip)
        vote_id = [date, sakskart_nr, subject, option_description].join(";")
        collapse(vote_id, "subject", subject)
        collapse(vote_id, "count_for", count_for)
        collapse(vote_id, "count_against", count_against)
        collapse(vote_id, "date", date)
        collapse(vote_id, "vote_time", vote_time)
        collapse(vote_id, "sakskart_nr", sakskart_nr)
        collapse(vote_id, "kart_nr", kart_nr)
        collapse(vote_id, "issue_id", @issue_map[[kart_nr,sakskart_nr]])
        if result_code == "Enstemmig vedtatt"
          collapse(vote_id, "unanimous", 1)
        elsif ! result_code.empty?
            abort "Unknown result code '#{result_code}'"
        else
          votes = @votes[vote_id]["votes"] ||= []
          @votes[vote_id]["votes"].push({ 
             "name" => name, "repr_nr" => repr_nr, "person_id" => person_id, 
             "party" => party, "district_code" => district_code, "vote" => vote
            })
        end
      end
    end
    @votes
  end

  private
  def collapse(vote_id, field, value)
    vote = @votes[vote_id] || @votes[vote_id] = {}
    old_value = vote[field]
    if old_value
        abort "Inconsistent value for field #{field}: #{old_value} != #{value}" if  old_value != value
    else
        vote[field] = value
    end
  end
end

class HdoVoteTranslator
  def initialize(votes)
    @votes = votes
  end

  def do_magic
    @votes.map do |vote_id, vote|
      {
        kind: 'hdo#vote',
        externalId: vote_id,
        externalIssueId: vote['issue_id'],
        counts: count(vote),
        personal: !vote['unanimous'],
        enacted: (count(vote)[:count_for] > count(vote)[:count_against] || vote['unanimous'] ? true : false), # this can't be right... where's the flag?? or, are 'unanimous' always enacted? because this is what this line assumes...
        subject: vote['subject'],
        method: "ikke_spesifisert",
        resultType: "ikke_spesifisert",
        time: Time.parse(vote['vote_time']).iso8601,
        representatives: representatives_for(vote)
      }
    end
  end

  private
  def representatives_for(vote)
    if vote['votes']
      vote['votes'].map do |rep_vote|
        {
          kind: "hdo#representative",
          externalId: rep_vote['person_id'],
          parties: [
            {
              kind: "hdo#partyMembership",
              externalId: rep_vote['party'],
            }
          ],
          voteResult: if rep_vote['vote'] == "J"; "for"; elsif rep_vote['vote'] == "N"; "against"; else; "absent"; end
        }
      end
    else
      []
    end
  end

  def count(vote)
    @counts ||= {}
    return @counts[vote] if @counts[vote]
    if(vote['votes'])
      counts = {
        count_for:     vote['count_for'].to_i,
        count_against: vote['count_against'].to_i,
        count_absent:  0
      }
      counts[:count_absent] = vote['votes'].count - counts[:count_for] - counts[:count_against]
    else
      counts = {
        count_for:     -1,
        count_against: -1,
        count_absent:  -1
      }
    end
    @counts[vote] = counts
  end
end

abort "Syntax: 155_to_json_oop issue_id_map_file vote_data_file" unless ARGV.count == 2
file1, file2 = ARGV

kart_to_issue_id_map = KartIssueMapper.new(file1).issue_map
votes = VoteParser.new(file2, kart_to_issue_id_map).votes

hdo_votes = HdoVoteTranslator.new(votes).do_magic


puts JSON.pretty_generate(hdo_votes)
