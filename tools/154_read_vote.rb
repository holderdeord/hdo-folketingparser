#!/usr/bin/env ruby

require 'pp'
require 'csv'
require 'json'
require 'time'
require 'pathname'
require 'pry'

class VoteReader
  attr_reader :identifier

  class << self
    include Enumerable

    def print_counts
      by_minutes.each do |minutes, votes|
        puts "#{minutes}"

        votes.sort_by { |e| e.time }.each do |vote|
          puts "\t #{vote.time.to_s.ljust(40)}: #{vote.counts.inspect}"
        end
      end
    end

    def by_minutes
      groups = Hash.new { |hash, key| hash[key] = [] }

      each do |votes|
        votes.each { |vote| groups[vote.minutes] << vote }
      end

      groups.sort_by { |m, v| m }
    end

    def find_errors
      cache = Pathname.new(File.expand_path('.minutes-cache'))
      cache.mkdir unless cache.exist?

      vote_count = 0
      error_count = 0

      by_minutes.each do |minutes, votes|
        vote_count += votes.size

        local_minutes = cache.join(File.basename(minutes))
        local_text    = cache.join(File.basename(minutes).gsub(".pdf", ".txt"))

        unless local_text.exist?
          unless local_minutes.exist?
            ok = system "curl -s -o #{local_minutes.to_s} #{minutes}"
            ok or raise "unable to download #{minutes}"
          end

          ok = system "java -jar ~/Downloads/pdfbox-app-1.7.1.jar ExtractText #{local_minutes} #{local_text.to_s}"
          ok or raise "could not convert #{local_minutes} to text"
        end

        lines        = local_text.read.split("\n")
        minute_votes = {}
        current_vote = nil

        lines.each_with_index do |line, index|
          case line
          when  "Vo t e r i n g :"
            current_vote = []
          when /Voteringsutskrift kl\. (\d{2}\.\d{2}\.\d{2})/
            next unless current_vote

            minute_votes[$1] = current_vote.join(" ")
            current_vote = nil
          when /enstemmig bifalt/
            current_vote = nil
          else
            current_vote << line if current_vote
          end
        end

        votes.sort_by { |e| e.time }.each do |vote|
          mvote  = minute_votes[vote.time.strftime("%H.%M.%S")]
          counts = vote.counts

          if mvote
            nums = mvote.scan(/\d+/).map { |e| e.to_i }
            unless nums.include?(counts[:for]) && nums.include?(counts[:against])
              error_count += 1

              if ENV['HTML']
                puts %{
                <tr>
                  <td><a href="#{minutes}">#{vote.time}</a></td>
                  <td>#{counts[:for]}</td>
                  <td>#{counts[:against]}</td>
                  <td>#{mvote}</td>
                </tr>
              }
              else
                puts "FEIL: #{vote.time} | for=#{counts[:for]}, mot=#{counts[:against]} | #{mvote}"
              end
            end
          end
        end
      end

      puts "#{error_count} / #{vote_count} = #{error_count * 100 / vote_count.to_f}%"
    end

    def each(&blk)
      Dir['./rawdata/stortinget-voteringer-154/*.154'].each do |path|
        if File.basename(path) =~ /SK(\d+)S(\d+)/
          yield VoteReader.new($1, $2).results
        else
          raise "bad path: #{path.inspect}"
        end
      end
    end
  end

  def initialize(kartnr, saknr)
    @kartnr     = kartnr
    @saknr      = saknr
    @identifier = "SK#{kartnr}S#{saknr}"
  end

  def results
    reps   = representatives
    result = {}

    votes.each do |time, vote_results|
      result[time] = vote_results.map.with_index do |result, idx|
        {:representative => reps[idx + 1], :seat => idx + 1, :result => result }
      end
    end

    result = result.map do |time, results|
      begin
        Vote.new(time, results, issue_for(time))
      rescue NoIssueFoundError => ex
        # trololol
        vote = Vote.allocate
        vote.instance_variable_set("@results", results)
        counts = vote.counts

        STDERR.puts "#{ex.message}: #{counts.inspect}"
      end
    end

    result.compact
  end

  private

  class NoIssueFoundError < StandardError
  end

  def issue_for(time)
    issue = issues[time]
    unless issue
      raise NoIssueFoundError, "no issue found for kartnr=#{@kartnr} saknr=#{@saknr} @ #{time}, found: #{issues.keys}\n #{issues.values.map { |e| e.first[:link] }.uniq}"
    end

    if issue.size == 1
      issue.first
    else
      raise "multiple issues for kartnr=#{@kartnr} saknr=#{@saknr} @ #{time}"
    end
  end

  def issues
    @issues ||= IssueFinder.find(@kartnr, @saknr).group_by { |data| data[:time] }
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
    attr_reader :time

    def initialize(time, results, issue)
      @time    = time
      @results = results
      @issue   = issue

      unless time == issue[:time]
        raise "time #{time.inspect} doesn't match issue: #{issue.inspect}"
      end

      @time = Time.parse(issue.values_at(:date, :time).join(' '))

      fix_handicap_seat
    end

    def minutes
      @issue.fetch(:link)
    end

    def saknr
      @issue.fetch(:saknr)
    end

    def kartnr
      @issue.fetch(:kartnr)
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

    def print(include_votes = true)
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

    def fix_handicap_seat
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


if __FILE__ == $0
  if ARGV.size == 2
    kartnr, saknr = ARGV
    results = VoteReader.new(kartnr, saknr).results
    results.first.print
  elsif ARGV.size == 1
    cmd = ARGV.first
    case cmd
    when 'print-counts'
      VoteReader.print_counts
    when 'find-errors'
      VoteReader.find_errors
    else
      raise "unknown command: #{cmd.inspect}"
    end
  end
end
