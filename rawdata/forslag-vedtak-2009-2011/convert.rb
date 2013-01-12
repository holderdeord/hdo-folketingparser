#!/usr/bin/env ruby

require 'json'
require 'nokogiri'
require 'time'
require 'pp'
require 'hdo/storting_importer'

# output is

# {
#   "<dato>:<motekartnr>:<dagsordensaksnr>": {
#     "kind": "hdo#proposition",
#     # ...
#   }
# }


# {
#   "kind": "hdo#proposition",
#   "externalId": "1234",
#   "description": "description",
#   "onBehalfOf": "on behalf of",
#   "body": "body",
#   "deliveredBy": {
#     "kind": "hdo#representative",
#     "externalId": "ADA",
#     "firstName": "André Oktay",
#     "lastName": "Dahl",
#     "gender": "M",
#     "dateOfBirth": "1975-07-07T00:00:00",
#     "dateOfDeath": "0001-01-01T00:00:00",
#     "district": "Akershus",
#     "parties": [
#       {
#         "kind": "hdo#partyMembership",
#         "externalId": "H",
#         "startDate": "2011-10-01",
#         "endDate": null
#       }
#     ],
#     "committees": [
#       {
#         "kind": "hdo#committeeMembership",
#         "externalId": "JUSTIS",
#         "startDate": "2011-10-01",
#         "endDate": null
#       }
#     ]
#   }
# }

module PropositionConverter
  class << self

    def from_2009
      xids = Set.new
      result = Hash.new { |hash, key| hash[key] = [] }

      doc = Nokogiri::XML.parse(File.read("./forslag-ikke-verifiserte-2009-2010.xml"))
      doc.css('IkkeKvalSikreteForslag').each_with_index do |node, idx|
        kartnr     = node.css('KartNr').first.text
        saksnr     = node.css('SaksNr').first.text
        date       = Time.parse(node.css('MoteDato').first.text).to_date

        desc_node   = node.css('Forslagsbetegnelse').first
        description = desc_node ? desc_node.text : ''

        body_node = node.css('ForslagTekst').first
        body = body_node ? body_node.text : ''

        external_id = "#{date.to_s}:#{idx}"
        key = "#{date.to_s}:#{kartnr}:#{saksnr}"

        if xids.include? external_id
          raise "duplicate xid #{external_id}: #{result[key].pretty_inspect}"
        end

        xids << external_id

        result[key] << Hdo::StortingImporter::Proposition.from_json({
          'kind'        => 'hdo#proposition',
          'description' => description.strip,
          'body'        => Hdo::StortingImporter::Util.remove_invalid_html(body.strip),
          'externalId'  => external_id,
          'onBehalfOf'  => '',
        }.to_json)
      end

      result
    end

    def from_2010
      xids = Set.new
      result = Hash.new { |hash, key| hash[key] = [] }

      doc = Nokogiri::XML.parse(File.read("./forslag-ikke-verifiserte-2010-2011.xml"))
      doc.css('IkkeKvalSikreteForslag').each_with_index do |node, idx|
        motekartnr     = node.css('MoteKartNr').first.text
        dagsordensaknr = node.css('DagsordenSaksNr').first.text
        time           = Time.parse(node.css('VoteringsTidspunkt').first.text)

        desc_node   = node.css('Forslagsbetegnelse').first
        description = desc_node ? desc_node.text : ''

        body_node = node.css('ForslagTekst').first
        body = body_node ? body_node.text : ''

        external_id = "#{time.to_s}:#{idx}"
        key = time.strftime('%Y-%m-%d %H:%M:%S.%L')

        if xids.include? external_id
          raise "duplicate xid #{external_id}: #{result[key].pretty_inspect}"
        end

        xids << external_id

        result[key] << Hdo::StortingImporter::Proposition.from_json({
          'kind'        => 'hdo#proposition',
          'description' => description.strip,
          'body'        => Hdo::StortingImporter::Util.remove_invalid_html(body.strip),
          'externalId'  => external_id,
          'onBehalfOf'  => '',
        }.to_json)
      end

      result
    end
  end
end

if __FILE__ == $0
  case ARGV.first
  when '2009-2010'
    puts PropositionConverter.from_2009.to_json
  when '2010-2011'
    puts PropositionConverter.from_2010.to_json
  else
    abort "USAGE: #{$PROGRAM_NAME} [2009-2010|2010-2011]"
  end
end