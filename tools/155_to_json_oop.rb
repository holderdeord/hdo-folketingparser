#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'json'


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

abort "Syntax: 155_to_json_oop issue_id_map_file vote_data_file" unless ARGV.count == 2
file1, file2 = ARGV

kart_to_issue_id_map = KartIssueMapper.new(file1).issue_map
votes = VoteParser.new(file2, kart_to_issue_id_map).votes

# puts JSON.pretty_generate(votes)
# hdo_votes = HdoVoteTranslator.new(votes).do_magic


