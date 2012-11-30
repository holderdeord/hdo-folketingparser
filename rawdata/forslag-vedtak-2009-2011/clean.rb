#
# script to clean invalid XML fra Stortinget (2012-11-30)
# 
# I'm only committing the cleaned result to avoid bloating this repo
# even more with an additional 20+ MB
#
# Received files @ Dropbox/HDO_Redaksjonen/Teknisk/Historiske\ data
# 

require 'nokogiri'

file = ARGV.first or abort "USAGE: #{$PROGRAM_NAME} /path/to/xml"

# read as ISO-8859-1
str = File.open(file, 'r:ISO-8859-1') { |io| io.read }

# add root element, which is missing
# str = "<root>#{str}</root>"

# encode as UTF-8
str.encode!('UTF-8')

# parse it ignoring blanks
doc = Nokogiri.XML(str) do |config|
  config.default_xml.noblanks
end

if doc.errors.any?
  raise "found errors:\n #{doc.errors.join("\n\t")}"
end

# print the result with 2-space indent
puts doc.to_xml(indent: 2)