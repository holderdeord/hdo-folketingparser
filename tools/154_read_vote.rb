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

  COLUMNS = %w[periode dato tid ses sal kart
              sak votnr typsak vottyp komite
              saksreferanse saksregister emne
              president presidentparti
              internkommentar lenke]

  def index
    @index ||= @data.inject({}) do |mem, var|
      issue = {}
      var.map(&:strip).each_with_index do |col, idx|
        issue[COLUMNS.fetch(idx).to_sym] = col
      end

      votes = mem[[issue[:kart], issue[:sak]]] ||= {}
      votes[issue[:votnr]] = issue

      mem
    end
  end
end

class VoteReader
  attr_reader :identifier

  def initialize(identifier)
    @identifier = identifier
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

  def combined
    reps   = representatives
    result = {}

    votes.each do |time, vote_results|
      result[time] = vote_results.map.with_index do |result, idx|
        {:representative => reps[idx + 1], :seat => idx + 1, :result => result }
      end
    end

    result.map { |time, results| Vote.new(time, results) }
  end

  class Vote
    def initialize(time, results)
      @time, @results = time, results
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
      puts "Tidspunkt    : #{@time.inspect}"
      puts "For          : #{counts[:for]}"
      puts "Mot          : #{counts[:against]}"
      puts "Ikke tilstede: #{counts[:absent]}"
      puts

      @results.sort_by { |v| v[:seat] }.each do |vote|
        puts "#{vote[:seat].to_s.ljust(3)}: #{vote[:representative].to_s.ljust(35)} : #{vote[:result]}"
      end
    end
  end
end

if __FILE__ == $0
  unless ARGV.size == 2
    abort "USAGE: #{$0} <kartnummer> <saksnummer>"
  end

  kartnr, saksnr = ARGV

  # pp IssueFinder.find(kartnr, saksnr)

  VoteReader.new("SK#{kartnr}S#{saksnr}").combined.first.print
end