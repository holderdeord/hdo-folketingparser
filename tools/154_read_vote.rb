#!/usr/bin/env ruby
# encoding: utf-8

require 'pp'
require 'csv'
require 'json'
require 'time'
require 'pathname'
require 'pry'
require 'erb'
require 'set'

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

    def count_representatives
      reps = Set.new

      each do |votes|
        votes.each do |v|
          v.results.each { |res| reps << res[:representative] }
        end
      end

      reps.to_a.size
    end

    def by_minutes
      groups = Hash.new { |hash, key| hash[key] = [] }

      each do |votes|
        votes.each { |vote| groups[vote.minutes] << vote }
      end

      groups.sort_by { |m, v| m }
    end

    def find_time(time)
      each do |votes|
        found = votes.find { |e| e.time == time }
        return found if found
      end

      nil
    end

    def find_errors
      cache = Pathname.new(File.expand_path('.minutes-cache'))
      cache.mkdir unless cache.exist?

      vote_count  = 0
      error_count = 0
      io          = CSV.new(STDOUT)

      io << Vote.csv_headers

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

        votes = votes.map do |vote|
          vote.minute_link = minutes
          vote.minute_text = minute_votes[vote.time.strftime("%H.%M.%S")]
          vote
        end

        votes.each do |vote|
          error_count += 1 if vote.invalid?
          io << vote.csv
        end
      end

      $stderr.puts "#{error_count} / #{vote_count} = (#{error_count * 100 / vote_count}%)"
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
        {:representative => parse_representative(reps[idx + 1]), :seat => idx + 1, :result => result }
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

  def parse_representative(str)
    return unless str

    if str =~ /^(.+)\s+([A-Z]+)$/
      {:name => $1.strip, :party => $2}
    else
      raise "unable to parse representative: #{str.inspect}"
    end
  end

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
    def self.csv_headers
      [
        "tidspunkt",
        "lenke",
        "stemmer med referatet?",
        "kartnr",
        "saknr",
        "president",
        "for",
        "mot",
        "blank",
        "totalt",
        "referat-tekst",
        "kommentar"
      ]
    end

    attr_reader :time, :errors, :results
    attr_accessor :minute_text, :minute_link

    def initialize(time, results, issue)
      @time    = time
      @results = results
      @issue   = issue

      unless time == issue[:time]
        raise "time #{time.inspect} doesn't match issue: #{issue.inspect}"
      end

      @comments = []

      @time = Time.parse(issue.values_at(:date, :time).join(' '))

      fix_handicap_seat
      fix_secretary_vote
      fix_president_vote
    end

    def csv
      c = counts()
      [
        time,
        minute_link,
        !invalid?,
        @issue[:kartnr],
        @issue[:saknr],
        president[:name],
        c[:for],
        c[:against],
        c[:absent],
        c.values.inject(0, &:+),
        minute_text,
        @comments.join(", ")
      ]
    end

    def invalid?
      if minute_text
        nums = minute_text.scan(/\d+/).map { |e| e.to_i }
        unless nums.include?(counts[:for]) && nums.include?(counts[:against])
          return true
        end
      end
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
    end

    def print(include_votes = true)
      puts "Tidspunkt     : #{@time.inspect}"
      puts "President     : #{president[:name]}"
      puts "For           : #{counts[:for]}"
      puts "Mot           : #{counts[:against]}"
      puts "Ikke tilstede : #{counts[:absent]}"
      puts "Referat       : #{@issue[:link]}"
      puts "Kommentar     : #{@comments.join(', ')}"
      puts

      if include_votes
        @results.sort_by { |v| v[:seat] }.each do |vote|
          puts "#{vote[:seat].to_s.ljust(3)}: #{(vote[:representative] || {}).values_at(:name, :party).join(' ').to_s.ljust(30)} : #{vote[:result]}"
        end
      end
    end

    def print_summary(io = $stdout, opts = {})
      if opts[:html]
        io.puts %{
        <tr>
          <td>#{time}</td>
          <td>#{counts[:for]}</td>
          <td>#{counts[:against]}</td>
          <td><a href="#{minute_link}">#{minute_text}</a></td>
          <td>#{comments.join(", ")}</td>
        </tr>
        }
      else
        msg = "#{time} | for=#{counts[:for].to_s.ljust(3)} mot=#{counts[:against].to_s.ljust(3)} | #{vote.minute_text}"
        msg <<  "| #{comments.inspect}" if vote.errors.any?

        io.puts msg
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
      elsif s172_result == "-" && s62_result != "-"
        @results.delete(s172)
      elsif s62_result == "-"
        s62[:result] = s172[:result]
        @results.delete(s172)
      else
        raise "oops: ##{[s62_result, s172_result].inspect} @ #{time} / #{minutes}"
      end
    end

    def fix_president_vote
      s170 = @results.find { |e| e[:seat] == 170 } or raise "could not find seat 170"

      pr = president
      actual_seat = @results.find { |e| e[:representative] == pr }
      actual_seat or raise "could not find actual seat for president: #{pr.inspect} in #{@results.inspect}"

      if s170[:result] == "-"
        @comments << "ingen stemme avgitt på presidentplass: #{s170.inspect}"
      end

      if actual_seat[:result] == "-"
        actual_seat[:result] = s170[:result]
        @results.delete(s170)
      elsif actual_seat[:result] == s170[:result]
        @comments << "presidenten stemte likt på begge plasser, #{inspect_result actual_seat} vs #{inspect_result s170}"
      elsif actual_seat[:result] != s170[:result]
        @comments << "presidenten stemte ulikt på begge plasser, #{inspect_result actual_seat} vs #{inspect_result s170}"
      end
    end

    def inspect_result(res)
      "#{res[:seat]}: #{res[:representative] && res[:representative][:name]} #{res[:result]}"
    end

    PRESIDENTS = {
      2259  => {name: 'D. T. Andersen', party: 'A'},
      2290  => {name: 'Ø. Korsberg', party: 'FRP'},
      30431 => {name: 'A. Chaudhry', party: 'SV'},
      204   => {name: 'P.-K. Foss', party: 'H'},
      1146  => {name: 'M. Nybakk', party: 'A'},
      31053 => {name: 'L. H. Holten Hjemdal', party: 'KRF'}
    }

    PRESIDENT_CORRECTIONS = {
      ["4", "1"]=>204,
      ["17", "1"]=>204,
      ["23", "4"]=>31053,
      ["23", "7"]=>31053,
      ["23", "9"]=>31053,
      ["25", "1"]=>30431,
      ["28", "10"]=>31053,
      ["28", "2"]=>31053,
      ["28", "5"]=>31053,
      ["28", "6"]=>31053,
      ["28", "7"]=>31053,
      ["28", "8"]=>31053,
      ["28", "9"]=>31053,
      ["29", "1"]=>31053,
      ["29", "7"]=>31053,
      ["30", "6"]=>2259,
      ["30", "7"]=>2259,
      ["31", "1"]=>1146,
      ["31", "10"]=>1146,
      ["31", "11"]=>1146,
      ["31", "6"]=>1146,
      ["31", "9"]=>1146,
      ["50", "4"]=>30431,
      ["50", "5"]=>30431,
      ["50", "6"]=>30431,
      ["50", "7"]=>30431,
      ["50", "8"]=>30431,
      ["54", "1"]=>1146,
      ["54", "11"]=>1146,
      ["54", "2"]=>1146,
      ["54", "3"]=>1146,
      ["54", "9"]=>1146,
      ["56", "15"]=>1146,
      ["56", "16"]=>1146,
      ["56", "17"]=>1146,
      ["56", "2"]=>1146,
      ["56", "3"]=>1146,
      ["56", "4"]=>1146,
      ["58", "3"]=>1146,
      ["59", "1"]=>2290,
      ["59", "3"]=>2290,
      ["59", "4"]=>2290,
      ["59", "5"]=>2290,
      ["59", "6"]=>2290,
      ["60", "1"]=>1146,
      ["60", "2"]=>1146,
      ["60", "3"]=>1146,
      ["60", "4"]=>1146,
      ["60", "5"]=>1146,
      ["64", "3"]=>31053,
      ["67", "4"]=>30431,
      ["67", "6"]=>30431,
      ["67", "7"]=>30431,
      ["68", "1"]=>2290,
      ["68", "3"]=>2290,
      ["70", "1"]=>1146,
      ["70", "2"]=>1146,
      ["70", "5"]=>1146,
      ["72", "2"]=>2290,
      ["72", "3"]=>2290,
      ["72", "4"]=>2290,
      ["72", "5"]=>2290,
      ["79", "1"]=>2290,
      ["79", "10"]=>2290,
      ["79", "2"]=>2290,
      ["79", "3"]=>2290,
      ["79", "4"]=>2290,
      ["79", "8"]=>2290,
      ["79", "9"]=>2290,
      ["85", "3"]=>204,
      ["88", "3"]=>30431,
      ["88", "4"]=>30431,
      ["88", "5"]=>30431,
      ["90", "1"]=>2259,
      ["90", "2"]=>2259,
      ["90", "3"]=>2259,
      ["90", "4"]=>2259,
      ["90", "5"]=>2259,
      ["90", "6"]=>2259,
      ["90", "7"]=>2259,
      ["90", "8"]=>2259,
      ["91", "12"]=>1146,
      ["91", "14"]=>1146,
      ["91", "15"]=>1146,
      ["91", "4"]=>1146,
      ["91", "5"]=>1146,
      ["91", "6"]=>1146,
      ["91", "9"]=>1146,
      ["92", "7"]=>1146,
      ["92", "8"]=>1146,
      ["95", "15"]=>2290,
      ["95", "16"]=>2290,
      ["95", "17"]=>2290,
      ["95", "18"]=>2290,
      ["95", "19"]=>2290,
      ["95", "20"]=>2290,
      ["95", "21"]=>2290,
      ["95", "22"]=>2290,
      ["95", "38"]=>2290,
      ["95", "39"]=>2290,
      ["95", "40"]=>2290,
      ["95", "41"]=>2290,
      ["96", "1"]=>31053,
      ["96", "13"]=>31053,
      ["96", "14"]=>31053,
      ["96", "15"]=>31053,
      ["96", "2"]=>31053,
      ["96", "3"]=>31053,
      ["96", "5"]=>31053,
      ["96", "6"]=>31053,
      ["96", "7"]=>31053,
      ["96", "8"]=>31053,
      ["96", "9"]=>31053,
      ["97", "2"]=>2259,
      ["97", "5"]=>2259,
      ["97", "6"]=>2259
    }

    def president
      PRESIDENTS.fetch(president_nsd_id.to_i) { raise "unknown president #{president_nsd_id} @ #{time} / #{minutes}"}
    end

    def president_nsd_id
      PRESIDENT_CORRECTIONS[[kartnr.to_s, saknr.to_s]] || @issue.fetch(:president)
    end

    def fix_secretary_vote
      secretary = @results.find { |e| e[:seat] == 171 }
      if secretary[:result] != "-"
        raise "the secretary voted: #{self.inspect}"
      else
        @results.delete(secretary)
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
    when /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \+\d{4}$/
      found = VoteReader.find_time(Time.parse(cmd))
      found.print if found
    else
      raise "unknown command: #{cmd.inspect}"
    end
  end
end
