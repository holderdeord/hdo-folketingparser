#!/usr/bin/env ruby
# encoding: UTF-8
require 'json'

INPUT = File.read ARGV[0]
VOTES = INPUT.scan /(\d{2}:\d{2}:\d{2})([FM\-]{172})/

RESULTS = VOTES.reduce({}) do |result, vote| 
  result[vote[0]] = vote[1].chars.reduce(Hash.new(0)) do |counts,c|
    counts[c] += 1
    counts
  end
  result
end

puts ARGV[0]
puts JSON.pretty_generate RESULTS