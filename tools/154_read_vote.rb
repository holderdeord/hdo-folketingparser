#!/usr/bin/env ruby
require 'pp'
require 'csv'
require 'json'

class IssueFinder
  def self.instance
    @instance ||= new
  end

  def self.find(kartnr, saknr)
    instance.index[[kartnr, saknr]]
  end

  def initialize
    @data ||= CSV.parse(File.read(("./rawdata/Fra NSD/154_saksopplysninger.csv")))
  end

  COLUMNS = %w[
    period
    date
    time
    session
    room
    kartnr
    saknr
    votnr
    issue_type
    vote_type
    committee
    issue_reference
    issue_register
    topic
    president
    president_party
    internal_comment
    link
  ]

  def index
    @index ||= @data.inject({}) do |mem, var|
      issue = {}

      var.map(&:strip).each_with_index do |col, idx|
        issue[COLUMNS.fetch(idx).to_sym] = col
      end

      if issue[:time] =~ /^0:/
        issue[:time] = "0#{issue[:time]}"
      end

      votes = mem[[issue[:kartnr], issue[:saknr]]] ||= []
      votes << issue

      mem
    end
  end
end

class VoteReader
  attr_reader :identifier

  def initialize(kartnr, saksnr)
    @kartnr     = kartnr
    @saksnr     = saksnr
    @identifier = "SK#{kartnr}S#{saksnr}"
  end

  def results
    reps   = representatives
    result = {}

    votes.each do |time, vote_results|
      result[time] = vote_results.map.with_index do |result, idx|
        {:representative => reps[idx + 1], :seat => idx + 1, :result => result }
      end
    end

    result.map do |time, results|
      Vote.new(time, results, issue_for(time))
    end
  end

  private

  def issue_for(time)
    issue = issues[time] or raise "no issue found for #{time}, found: #{issues.keys}"

    if issue.size == 1
      issue.first
    else
      raise "multiple issues for timestamp: #{time.inspect}"
    end
  end

  def issues
    @issues ||= IssueFinder.find(@kartnr, @saksnr).group_by { |data| data[:time] }
  end

  def representatives
    files = Dir["./rawdata/stortinget-voteringer-154/#{identifier}.R*"]

    unless files.size == 1
      raise "expected 1 file of representatives, got #{files.inspect}"
    end

    file = files.first

    content = File.read(file)[2..-1]
    result = {}

    content.scan(/.{35}/).map { |e| e.strip }.map do |line|
      if line =~ /^(\d+): (.+)$/
        result[$1.to_i] = $2
      end
    end

    unless result.size == 169
      raise "incorrect number of reps for #{identifier}: #{result.size}\n#{result.pretty_inspect}"
    end

    result
  end

  def votes
    content = File.read("./rawdata/stortinget-voteringer-154/#{identifier}.154")

    votes = {}
    content.scan(/(\d{2}:\d{2}:\d{2})([FM-]+)/).each do |time, vote_string|
      votes[time] = vote_string.split(//)
    end

    votes
  end

  class Vote
    def initialize(time, results, issue)
      @time    = time
      @results = results
      @issue   = issue

      check_handicap_seat
    end

    def counts
      @counts ||= (
        c = {:for => 0, :against => 0, :absent => 0}

        @results.each do |vote|
          case vote[:result]
          when 'F'
            c[:for] += 1
          when 'M'
            c[:against] += 1
          when '-'
            c[:absent] += 1
          else
            raise "unknown result: #{vote[:result].inspect}"
          end
        end

        c
      )
    end

    def print
      puts "Tidspunkt     : #{@time.inspect}"
      puts "For           : #{counts[:for]}"
      puts "Mot           : #{counts[:against]}"
      puts "Ikke tilstede : #{counts[:absent]}"
      puts "Referat       : #{@issue[:link]}"
      puts

      @results.sort_by { |v| v[:seat] }.each do |vote|
        puts "#{vote[:seat].to_s.ljust(3)}: #{vote[:representative].to_s.ljust(35)} : #{vote[:result]}"
      end
    end

    private

    def check_handicap_seat
      s62  = @results.find { |e| e[:seat] == 62 }
      s172 = @results.find { |e| e[:seat] == 172 }

      s62_result  = s62[:result]
      s172_result = s172[:result]

      if s62_result == s172_result
        @results.delete s172
      elsif s172_result == "-"
        # ignored
      elsif s62_result == "-"
        s172[:representative] = s62.delete(:representative)
      else
        raise "oops: ##{[s62_result, s172_result].inspect}"
      end
    end

  end
end

if __FILE__ == $0
  if ARGV.size == 2
    kartnr, saksnr = ARGV
    results = VoteReader.new(kartnr, saksnr).results
    results.first.print
  else
    # TODO: read all
    abort "USAGE: #{$0} <kartnummer> <saksnummer>"
  end
end