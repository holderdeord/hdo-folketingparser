#!/usr/bin/env ruby

require 'json'
require 'nokogiri'
require 'time'
require 'hdo/storting_importer'
require 'pp'

module VedtakConverter
  class << self

    def from_2009
      xids = Set.new
      result = Hash.new { |hash, key| hash[key] = [] }

      doc = Nokogiri::XML.parse(File.read("./vedtak-2009-2010.xml"))
      doc.css('Vedtak').each_with_index do |node, idx|
        kartnr     = node.css('KartNr').first.text
        saksnr     = node.css('SaksNr').first.text
        # date       = Time.parse(node.css('MoteDato').first.text).to_date

        desc_node   = node.css('Forslagsbetegnelse').first
        description = desc_node ? desc_node.text : ''

        body_node = node.css('Vedtakstekst').first
        next unless body_node
        body = body_node ? body_node.text : ''

        external_id = "#{kartnr}:#{saksnr}:#{idx}"
        key = "#{kartnr}:#{saksnr}"

        if xids.include? external_id
          raise "duplicate xid #{external_id}: #{result[key].pretty_inspect}"
        end

        xids << external_id

        # result[key] << Hdo::StortingImporter::Proposition.from_json({
        #   'kind'        => 'hdo#proposition',
        #   'description' => description.strip,
        #   'body'        => Hdo::StortingImporter::Util.remove_invalid_html(body.strip),
        #   'externalId'  => external_id,
        #   'onBehalfOf'  => '',
        # }.to_json)

        result[key] <<
        {
          'kind'        => 'hdo#proposition',
          'description' => description.strip,
          'body'        => Hdo::StortingImporter::Util.remove_invalid_html(body.strip),
          'externalId'  => external_id,
          'onBehalfOf'  => ''
        }
      end

      result
    end
  end
end

if __FILE__ == $0
  # puts VedtakConverter.from_2009.to_json
  puts VedtakConverter.from_2009.to_json
end