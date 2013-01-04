#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'json'
require 'time'
require 'set'

class KartIssueMapper
  def initialize(filename)
    @file = File.new(filename)
  end

  def issue_map
    unless @issue_map
      @issue_map = {}
      @file.lines.each do |line|
        date, kart_nr, issue_id, sakskart_nr, short_text = line.split("\t").map(&:strip)
        @issue_map[[kart_nr, sakskart_nr, date]] ||= []
        @issue_map[[kart_nr, sakskart_nr, date]] << issue_id
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
      @votes_without_issues = Set.new
      @votes = {}
      @file.lines.each do |line|
        (date, kart_nr, sakskart_nr, vote_time, subject, option_description,
         result_code, count_for, count_against, name, repr_nr, person_id, 
         party, district_code, vote, option) = line.split(";").map(&:strip)
        vote_id = [date, sakskart_nr, subject, option_description].join(";")
        # abort "dont have issue_id for kartnr,sakskart_nr #{kart_nr},#{sakskart_nr}" unless @issue_map[[kart_nr,sakskart_nr]]
        @votes_without_issues << "#{kart_nr},#{sakskart_nr}" unless @issue_map[[kart_nr,sakskart_nr]]
        @issue_map[[kart_nr,sakskart_nr,date]].each do |issue_id|
          next if ['44301','44302','44682','44683'].include? issue_id
          collapse(vote_id, "subject", subject)
          collapse(vote_id, "count_for", count_for)
          collapse(vote_id, "count_against", count_against)
          collapse(vote_id, "date", date)
          collapse(vote_id, "vote_time", vote_time)
          collapse(vote_id, "sakskart_nr", sakskart_nr)
          collapse(vote_id, "kart_nr", kart_nr)
          # collapse(vote_id, "issue_id", issue_id)
          add_issue_id_to(vote_id, issue_id)
          if result_code == "Enstemmig vedtatt"
            collapse(vote_id, "unanimous", 1)
          elsif ! result_code.empty?
              abort "Unknown result code '#{result_code}'"
          else
            @votes[vote_id]["votes"] ||= []
            @votes[vote_id]["votes"].push({
               "name" => name, "repr_nr" => repr_nr, "person_id" => person_id,
               "party" => party, "district_code" => district_code, "vote" => vote
              }) if @votes[vote_id]['votes'].select { |v| v['person_id'] == person_id }.empty?
          end
        end if @issue_map[[kart_nr,sakskart_nr,date]]
        # unless @votes_without_issues.empty?
        #   puts JSON.pretty_generate(@votes_without_issues.to_a)
        #   abort "some votes didnt have issue ids in the mapping file."
        # end
      end
    end
    @votes
  end

  private
  def add_issue_id_to(vote_id, issue_id)
    vote = @votes[vote_id]
    vote['issue_id'] ||= Set.new
    vote['issue_id'] << issue_id
  end

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
  def initialize(votes, reps, props)
    @missing_reps = {}
    @props = props
    @votes = votes
    @reps  = reps.reduce({}) do |result, rep|
      result[rep['externalId']] = rep
      result
    end
    @representatives_set = Set.new
  end

  def hdo_reps
    @representatives_set.to_a
  end

  def do_magic
    magic = @votes.map do |vote_id, vote|
      vote['issue_id'].map do |issue_id|
        {
          kind:            'hdo#vote',
          externalId:      vote['vote_time'] + (enacted?(vote) ? 'j' : 'n'),
          externalIssueId: issue_id, #vote['issue_id'],
          counts:          count(vote),
          personal:        !vote['unanimous'],
          enacted:         enacted?(vote),
          subject:         vote['subject'],
          method:          "ikke_spesifisert",
          resultType:      "ikke_spesifisert",
          time:            Time.parse(vote['vote_time']).iso8601,
          representatives: representatives_for(vote),
          propositions:    props_for(vote)
        }
      end
    end.flatten
    if !@missing_reps.empty?
      puts JSON.pretty_generate @missing_reps.to_a
      abort "missing some representatives, yo.."
    end
    magic
  end

  private
  def enacted?(vote)
    (count(vote)[:for] > count(vote)[:against] || vote['unanimous'] ? true : false) # this can't be right... where's the flag?? or, are 'unanimous' always enacted? because this is what this line assumes...
  end

  def representatives_for(vote)
    if vote['votes']
      vote['votes'].map do |rep_vote|
        rep = @reps[rep_vote['person_id']]
        abort "rep #{rep} changed parties" if rep && rep['parties'].first['externalId'] != rep_vote['party']
        unless rep
          rep = ghost(rep_vote)
          @missing_reps[rep[:externalId]] = rep
        end
        @representatives_set << rep
        {
          voteResult: if rep_vote['vote'] == "J"; "for"; elsif rep_vote['vote'] == "N"; "against"; else; "absent"; end
        }.merge (rep || ghost(rep_vote))
      end
    else
      []
    end
  end
  def props_for(vote)
    @props[vote['vote_time']] || []
  end

  def ghost(rep_vote)
    last_name, first_name = rep_vote['name'].split(',')
    {
    kind: "hdo#representative",
    externalId: rep_vote['person_id'],
    firstName: first_name,
    lastName: last_name,
    dateOfBirth: Time.now,
    dateOfDeath: nil,
    district: rep_vote['district_code'],
    parties: [
      {
        kind: "hdo#partyMembership",
        externalId: rep_vote['party'],
        startDate: nil,
        endDate: nil
      }
    ],
    committees: []
  }
  end

  def count(vote)
    @counts ||= {}
    return @counts[vote] if @counts[vote]
    if(vote['votes'])
      counts = {
        for:     vote['count_for'].to_i,
        against: vote['count_against'].to_i,
        absent:  0
      }
      counts[:absent] = vote['votes'].count - counts[:for] - counts[:against]
      # puts JSON.pretty_generate(vote['votes'])
      # abort vote['votes'].count.to_s if counts[:absent] > 400

      if counts[:absent] > 400
        puts JSON.pretty_generate(vote)
        abort "I think you have some duplicate votes somewhere..."
      end
    else
      counts = {
        for:     0,
        against: 0,
        absent:  0
      }
    end
    @counts[vote] = counts
  end
end

abort "Syntax: 155_to_json_oop prop_file issue_id_map_file vote_data_file" unless ARGV.count == 3
prop_file, kart_issue_file, vote_file = ARGV

kart_to_issue_id_map = KartIssueMapper.new(kart_issue_file).issue_map

votes = VoteParser.new(vote_file, kart_to_issue_id_map).votes
reps  = JSON.parse(DATA.read)
props = JSON.parse(File.read(prop_file))

hdo_translator = HdoVoteTranslator.new(votes, reps, props)
hdo_votes = hdo_translator.do_magic

puts JSON.pretty_generate([hdo_translator.hdo_reps, hdo_votes].flatten)

__END__
[
  {
    "kind": "hdo#representative",
    "externalId": "KFOS",
    "firstName": "Kåre",
    "lastName": "Fostervold",
    "dateOfBirth": "1969-10-10",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LBT",
    "firstName": "Lars Bjarne",
    "lastName": "Tvete",
    "dateOfBirth": "1948-1-4",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HCI",
    "firstName": "Hanne C.S.",
    "lastName": "Iversen",
    "dateOfBirth": "1977-11-14",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EAG",
    "firstName": "Elin Rodum",
    "lastName": "Agdestein",
    "dateOfBirth": "1957-8-10",
    "dateOfDeath": null,
    "district": "Nord-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LKE",
    "firstName": "Lasse Kinden",
    "lastName": "Endresen",
    "dateOfBirth": "1989-12-18",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BROS",
    "firstName": "Brigt",
    "lastName": "Samdal",
    "dateOfBirth": "1970-5-14",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KRV",
    "firstName": "Kristin",
    "lastName": "Vinje",
    "dateOfBirth": "1963-6-10",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "RAK",
    "firstName": "Ragnhild Aarflot",
    "lastName": "Kalland",
    "dateOfBirth": "1960-9-4",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "FRS",
    "firstName": "Fredrik",
    "lastName": "Sletbakk",
    "dateOfBirth": "1990-03-22",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MHE",
    "firstName": "Martin",
    "lastName": "Henriksen",
    "dateOfBirth": "1979-1-5",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ALER",
    "firstName": "Ann-Hege",
    "lastName": "Lervåg",
    "dateOfBirth": "1974-5-20",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BIM",
    "firstName": "Bjørn Inge",
    "lastName": "Mo",
    "dateOfBirth": "1968-3-16",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "RFN",
    "firstName": "Ragnar",
    "lastName": "Nordgreen",
    "dateOfBirth": "1946-8-11",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MKE",
    "firstName": "Mazyar",
    "lastName": "Keshvari",
    "dateOfBirth": "1981-3-5",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
  "kind": "hdo#representative",
  "externalId": "AJI",
  "firstName": "Anne June",
  "lastName": "Iversen",
  "dateOfBirth": "1964-02-04",
  "dateOfDeath": null,
  "district": "Sogn og Fjordane",
  "parties": [
    {
      "kind": "hdo#partyMembership",
      "externalId": "FrP",
      "startDate": "2009-10-01",
      "endDate": "2010-9-30"
    }
  ],
  "committees": [

  ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AENG",
    "firstName": "Ann-Kristin",
    "lastName": "Engstad",
    "dateOfBirth": "1982-04-05",
    "dateOfDeath": null,
    "district": "Finnmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "PAMB",
    "firstName": "Pål Morten",
    "lastName": "Borgli",
    "dateOfBirth": "1967-12-03",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ELV",
    "firstName": "Hårek",
    "lastName": "Elvenes",
    "dateOfBirth": "1959-06-17",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "DS",
    "firstName": "Dag",
    "lastName": "Sele",
    "dateOfBirth": "1964-4-3",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TSOL",
    "firstName": "Tom Strømstad",
    "lastName": "Olsen",
    "dateOfBirth": "1971-9-12",
    "dateOfDeath": null,
    "district": "Vestfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "IAS",
    "firstName": "Ivar",
    "lastName": "Skulstad",
    "dateOfBirth": "1953-5-6",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TAR",
    "firstName": "Tomas C.",
    "lastName": "Archer",
    "dateOfBirth": "1952-8-31",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HNJ",
    "firstName": "Helge André",
    "lastName": "Njåstad",
    "dateOfBirth": "1980-6-5",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ANES",
    "firstName": "Anette Stegegjerdet",
    "lastName": "Norberg",
    "dateOfBirth": "1986-12-24",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EINH",
    "firstName": "Einar",
    "lastName": "Horvei",
    "dateOfBirth": "1955-1-3",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MAAA",
    "firstName": "Marianne",
    "lastName": "Aasen",
    "dateOfBirth": "1967-02-20T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TELA",
    "firstName": "Terje",
    "lastName": "Aasland",
    "dateOfBirth": "1965-02-14T23:00:00Z",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "RIAJ",
    "firstName": "Rigmor",
    "lastName": "Aasrud",
    "dateOfBirth": "1960-06-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KAGE",
    "firstName": "Kari",
    "lastName": "Agerup",
    "dateOfBirth": "1951-07-04T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TAML",
    "firstName": "Torkil",
    "lastName": "Åmland",
    "dateOfBirth": "1966-12-22T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "PTA",
    "firstName": "Per-Willy",
    "lastName": "Amundsen",
    "dateOfBirth": "1971-01-20T23:00:00Z",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MARI",
    "firstName": "Marit",
    "lastName": "Amundsen",
    "dateOfBirth": "1968-09-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "DTA",
    "firstName": "Dag Terje",
    "lastName": "Andersen",
    "dateOfBirth": "1957-05-26T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vestfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KAAN",
    "firstName": "Karin",
    "lastName": "Andersen",
    "dateOfBirth": "1952-12-15T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "RAA",
    "firstName": "Rannveig Kvifte",
    "lastName": "Andresen",
    "dateOfBirth": "1967-05-18T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ANA",
    "firstName": "Anders",
    "lastName": "Anundsen",
    "dateOfBirth": "1975-11-16T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vestfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KONTROLL",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MLA",
    "firstName": "Mari Lund",
    "lastName": "Arnem",
    "dateOfBirth": "1986-01-26T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BEHA",
    "firstName": "Bendiks H.",
    "lastName": "Arnesen",
    "dateOfBirth": "1951-06-08T23:00:00Z",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HAFA",
    "firstName": "Hans Frode Kielland",
    "lastName": "Asmyhr",
    "dateOfBirth": "1970-02-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EAS",
    "firstName": "Elisabeth",
    "lastName": "Aspaker",
    "dateOfBirth": "1962-10-15T23:00:00Z",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JASP",
    "firstName": "Jorodd",
    "lastName": "Asphjell",
    "dateOfBirth": "1960-07-16T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "NA",
    "firstName": "Nikolai",
    "lastName": "Astrup",
    "dateOfBirth": "1978-06-11T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EVA",
    "firstName": "Eva Vinje",
    "lastName": "Aurdal",
    "dateOfBirth": "1957-12-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AGEA",
    "firstName": "Åge",
    "lastName": "Austheim",
    "dateOfBirth": "1983-11-19T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "FB",
    "firstName": "Farahnaz",
    "lastName": "Bahrami",
    "dateOfBirth": "1962-03-20T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "FBJ",
    "firstName": "Frank",
    "lastName": "Bakke-Jensen",
    "dateOfBirth": "1965-03-07T23:00:00Z",
    "dateOfDeath": null,
    "district": "Finnmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GKB",
    "firstName": "Gina Knutson",
    "lastName": "Barstad",
    "dateOfBirth": "1986-04-27T22:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GJB",
    "firstName": "Geir Jørgen",
    "lastName": "Bekkevold",
    "dateOfBirth": "1963-11-18T23:00:00Z",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KONTROLL",
        "startDate": "2011-10-01",
        "endDate": null
      },
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BERG",
    "firstName": "Arne",
    "lastName": "Bergsvåg",
    "dateOfBirth": "1958-02-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ANMB",
    "firstName": "Anne Marit",
    "lastName": "Bjørnflaten",
    "dateOfBirth": "1969-06-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JBO",
    "firstName": "Jan",
    "lastName": "Bøhler",
    "dateOfBirth": "1952-02-29T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ODB",
    "firstName": "Odin Adelsten",
    "lastName": "Bohmann",
    "dateOfBirth": "1985-06-04T22:00:00Z",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MGB",
    "firstName": "Marion Gunstveit",
    "lastName": "Bojanowski",
    "dateOfBirth": "1966-05-15T23:00:00Z",
    "dateOfDeath": null,
    "district": "Aust-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EBO",
    "firstName": "Else-May",
    "lastName": "Botten",
    "dateOfBirth": "1973-08-15T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TLB",
    "firstName": "Tove Linnea",
    "lastName": "Brandvik",
    "dateOfBirth": "1968-11-14T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SUB",
    "firstName": "Susanne",
    "lastName": "Bratli",
    "dateOfBirth": "1966-06-09T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nord-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "PB",
    "firstName": "Per Roar",
    "lastName": "Bredvold",
    "dateOfBirth": "1957-03-04T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "THB",
    "firstName": "Thomas",
    "lastName": "Breen",
    "dateOfBirth": "1972-09-12T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LAPB",
    "firstName": "Lars Peder",
    "lastName": "Brekk",
    "dateOfBirth": "1955-10-07T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nord-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2012-10-06",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TBRE",
    "firstName": "Tor",
    "lastName": "Bremer",
    "dateOfBirth": "1955-02-08T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HAB",
    "firstName": "Hallgeir",
    "lastName": "Bremnes",
    "dateOfBirth": "1971-04-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TIB",
    "firstName": "Tina",
    "lastName": "Bru",
    "dateOfBirth": "1986-04-17T22:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AC",
    "firstName": "Akhtar",
    "lastName": "Chaudhry",
    "dateOfBirth": "1961-07-22T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JFC",
    "firstName": "Jette F.",
    "lastName": "Christensen",
    "dateOfBirth": "1983-05-31T22:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KONTROLL",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LIC",
    "firstName": "Lise",
    "lastName": "Christoffersen",
    "dateOfBirth": "1955-08-04T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TORD",
    "firstName": "Torgeir",
    "lastName": "Dahl",
    "dateOfBirth": "1953-12-12T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ADA",
    "firstName": "André Oktay",
    "lastName": "Dahl",
    "dateOfBirth": "1975-07-06T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JGD",
    "firstName": "Jon Georg",
    "lastName": "Dale",
    "dateOfBirth": "1984-06-15T22:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LD",
    "firstName": "Laila",
    "lastName": "Dåvøy",
    "dateOfBirth": "1948-08-10T22:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": "2012-09-30"
      },
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2012-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "FR",
    "firstName": "Freddy",
    "lastName": "de Ruiter",
    "dateOfBirth": "1969-04-03T23:00:00Z",
    "dateOfDeath": null,
    "district": "Aust-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MD",
    "firstName": "Morten",
    "lastName": "Drægni",
    "dateOfBirth": "1983-08-18T22:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TDY",
    "firstName": "Torbjørn",
    "lastName": "Dybsand",
    "dateOfBirth": "1966-02-02T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SOE",
    "firstName": "Sonja",
    "lastName": "Edvardsen",
    "dateOfBirth": "1960-10-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LAE",
    "firstName": "Lars",
    "lastName": "Egeland",
    "dateOfBirth": "1957-12-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vestfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SHEG",
    "firstName": "Siri Hov",
    "lastName": "Eggen",
    "dateOfBirth": "1969-12-07T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MAGE",
    "firstName": "Magnhild",
    "lastName": "Eia",
    "dateOfBirth": "1960-01-14T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "RAE",
    "firstName": "Rigmor Andersen",
    "lastName": "Eide",
    "dateOfBirth": "1954-06-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GUE",
    "firstName": "Gunvor",
    "lastName": "Eldegard",
    "dateOfBirth": "1963-04-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JAE",
    "firstName": "Jan Arild",
    "lastName": "Ellingsen",
    "dateOfBirth": "1958-10-08T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "OLE",
    "firstName": "Ola",
    "lastName": "Elvestuen",
    "dateOfBirth": "1967-10-08T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "V",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "DE",
    "firstName": "Dagrun",
    "lastName": "Eriksen",
    "dateOfBirth": "1971-06-27T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vest-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "RE",
    "firstName": "Robert",
    "lastName": "Eriksson",
    "dateOfBirth": "1974-04-22T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nord-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MF",
    "firstName": "Monica",
    "lastName": "Finden",
    "dateOfBirth": "1969-10-23T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GFL",
    "firstName": "Gunn Elin",
    "lastName": "Flakne",
    "dateOfBirth": "1964-01-07T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SAF",
    "firstName": "Svein",
    "lastName": "Flåtten",
    "dateOfBirth": "1944-10-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vestfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TEF",
    "firstName": "Thor Erik",
    "lastName": "Forsberg",
    "dateOfBirth": "1980-04-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "PKF",
    "firstName": "Per-Kristian",
    "lastName": "Foss",
    "dateOfBirth": "1950-07-18T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KONTROLL",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "VIF",
    "firstName": "Viggo",
    "lastName": "Fossum",
    "dateOfBirth": "1949-12-03T23:00:00Z",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JF",
    "firstName": "Jan-Henrik",
    "lastName": "Fredriksen",
    "dateOfBirth": "1956-10-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Finnmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MCG",
    "firstName": "Monica Carmen",
    "lastName": "Gåsvatn",
    "dateOfBirth": "1968-05-08T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JONG",
    "firstName": "Jon Jæger",
    "lastName": "Gåsvatn",
    "dateOfBirth": "1954-06-18T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "VKG",
    "firstName": "Vigdis",
    "lastName": "Giltun",
    "dateOfBirth": "1952-03-10T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TG",
    "firstName": "Trond",
    "lastName": "Giske",
    "dateOfBirth": "1966-11-06T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "PEG",
    "firstName": "Peter Skovholt",
    "lastName": "Gitmark",
    "dateOfBirth": "1977-04-14T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vest-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SAG",
    "firstName": "Svein",
    "lastName": "Gjelseth",
    "dateOfBirth": "1950-02-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GKG",
    "firstName": "Gunn Karin",
    "lastName": "Gjul",
    "dateOfBirth": "1967-07-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "IAG",
    "firstName": "Ingebjørg",
    "lastName": "Godskesen",
    "dateOfBirth": "1957-05-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Aust-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SYG",
    "firstName": "Sylvi",
    "lastName": "Graham",
    "dateOfBirth": "1951-12-16T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TSG",
    "firstName": "Trine Skei",
    "lastName": "Grande",
    "dateOfBirth": "1969-10-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "V",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KONTROLL",
        "startDate": "2011-10-01",
        "endDate": null
      },
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KGRA",
    "firstName": "Knut",
    "lastName": "Gravråk",
    "dateOfBirth": "1985-05-14T22:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HEIG",
    "firstName": "Heidi",
    "lastName": "Greni",
    "dateOfBirth": "1962-07-02T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "OG",
    "firstName": "Oskar J.",
    "lastName": "Grimstad",
    "dateOfBirth": "1954-11-07T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "OLOG",
    "firstName": "Olov",
    "lastName": "Grøtting",
    "dateOfBirth": "1960-09-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2012-10-06",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "STEG",
    "firstName": "Steinar",
    "lastName": "Gullvåg",
    "dateOfBirth": "1946-10-26T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vestfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GAG",
    "firstName": "Gunnar",
    "lastName": "Gundersen",
    "dateOfBirth": "1956-05-20T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LAG",
    "firstName": "Laila",
    "lastName": "Gustavsen",
    "dateOfBirth": "1973-10-23T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ØH",
    "firstName": "Øyvind",
    "lastName": "Håbrekke",
    "dateOfBirth": "1969-12-19T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TOHA",
    "firstName": "Tore",
    "lastName": "Hagebakken",
    "dateOfBirth": "1961-01-07T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AKSH",
    "firstName": "Aksel",
    "lastName": "Hagen",
    "dateOfBirth": "1953-10-03T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GJH",
    "firstName": "Gjermund",
    "lastName": "Hagesæter",
    "dateOfBirth": "1960-12-11T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "STRH",
    "firstName": "Stine Renate",
    "lastName": "Håheim",
    "dateOfBirth": "1984-05-12T22:00:00Z",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TERH",
    "firstName": "Terje",
    "lastName": "Halleland",
    "dateOfBirth": "1966-04-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ØYVH",
    "firstName": "Øyvind",
    "lastName": "Halleraker",
    "dateOfBirth": "1951-10-26T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KHA",
    "firstName": "Kristin",
    "lastName": "Halvorsen",
    "dateOfBirth": "1960-09-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "METH",
    "firstName": "Mette",
    "lastName": "Hanekamhaug",
    "dateOfBirth": "1987-06-03T22:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SOH",
    "firstName": "Sigvald Oppebøen",
    "lastName": "Hansen",
    "dateOfBirth": "1950-09-20T23:00:00Z",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SRH",
    "firstName": "Svein Roald",
    "lastName": "Hansen",
    "dateOfBirth": "1949-08-19T22:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GEHN",
    "firstName": "Geir-Ketil",
    "lastName": "Hansen",
    "dateOfBirth": "1956-03-12T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LILH",
    "firstName": "Lillian",
    "lastName": "Hansen",
    "dateOfBirth": "1957-05-16T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EVH",
    "firstName": "Eva Kristin",
    "lastName": "Hansen",
    "dateOfBirth": "1973-03-04T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KBH",
    "firstName": "Kjell Børre",
    "lastName": "Hansen",
    "dateOfBirth": "1957-05-04T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LHA",
    "firstName": "Lars Joakim",
    "lastName": "Hanssen",
    "dateOfBirth": "1975-10-21T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SHAR",
    "firstName": "Svein",
    "lastName": "Harberg",
    "dateOfBirth": "1958-07-29T23:00:00Z",
    "dateOfDeath": null,
    "district": "Aust-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KNAH",
    "firstName": "Knut Arild",
    "lastName": "Hareide",
    "dateOfBirth": "1972-11-22T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ROAH",
    "firstName": "Roald Aga",
    "lastName": "Haug",
    "dateOfBirth": "1972-07-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ARLH",
    "firstName": "Arne L.",
    "lastName": "Haugen",
    "dateOfBirth": "1939-07-24T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ASKH",
    "firstName": "Åshild Karoline",
    "lastName": "Haugland",
    "dateOfBirth": "1986-11-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Aust-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HAKH",
    "firstName": "Håkon",
    "lastName": "Haugli",
    "dateOfBirth": "1969-05-20T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "IHE",
    "firstName": "Ingrid",
    "lastName": "Heggø",
    "dateOfBirth": "1961-08-11T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LCH",
    "firstName": "Linda C. Hofstad",
    "lastName": "Helleland",
    "dateOfBirth": "1977-08-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TROH",
    "firstName": "Trond",
    "lastName": "Helleland",
    "dateOfBirth": "1962-07-09T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AREH",
    "firstName": "Are",
    "lastName": "Helseth",
    "dateOfBirth": "1955-01-10T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "PRH",
    "firstName": "Per Rune",
    "lastName": "Henriksen",
    "dateOfBirth": "1960-03-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KARH",
    "firstName": "Kari",
    "lastName": "Henriksen",
    "dateOfBirth": "1955-08-09T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vest-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "CSH",
    "firstName": "Camilla Storøy",
    "lastName": "Hermansen",
    "dateOfBirth": "1979-01-27T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LHH",
    "firstName": "Line Henriette",
    "lastName": "Hjemdal",
    "dateOfBirth": "1971-10-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": "2012-09-30"
      },
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2012-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MORH",
    "firstName": "Morten",
    "lastName": "Høglund",
    "dateOfBirth": "1965-07-15T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BENH",
    "firstName": "Bent",
    "lastName": "Høie",
    "dateOfBirth": "1971-05-03T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BÅH",
    "firstName": "Bård",
    "lastName": "Hoksrud",
    "dateOfBirth": "1973-03-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "IDH",
    "firstName": "Ida Marie",
    "lastName": "Holen",
    "dateOfBirth": "1958-03-28T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HEH",
    "firstName": "Heikki Eidsvoll",
    "lastName": "Holmås",
    "dateOfBirth": "1972-06-27T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ALEH",
    "firstName": "Alf Egil",
    "lastName": "Holmelid",
    "dateOfBirth": "1947-12-12T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vest-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SHK",
    "firstName": "Solveig",
    "lastName": "Horne",
    "dateOfBirth": "1969-01-11T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "DH",
    "firstName": "Dagfinn",
    "lastName": "Høybråten",
    "dateOfBirth": "1957-12-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ANNH",
    "firstName": "Anniken",
    "lastName": "Huitfeldt",
    "dateOfBirth": "1969-11-28T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TRI",
    "firstName": "Torbjørn Røe",
    "lastName": "Isaksen",
    "dateOfBirth": "1978-07-27T23:00:00Z",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SIVJ",
    "firstName": "Siv",
    "lastName": "Jensen",
    "dateOfBirth": "1969-05-31T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AJO",
    "firstName": "Allan",
    "lastName": "Johansen",
    "dateOfBirth": "1947-05-12T21:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MOJ",
    "firstName": "Morten Ørsal",
    "lastName": "Johansen",
    "dateOfBirth": "1964-09-10T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "IJ",
    "firstName": "Irene",
    "lastName": "Johansen",
    "dateOfBirth": "1961-01-06T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": "2012-10-26"
      },
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2012-10-27",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EJ",
    "firstName": "Espen Granberg",
    "lastName": "Johnsen",
    "dateOfBirth": "1976-10-16T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LAJ",
    "firstName": "Lasse",
    "lastName": "Juliussen",
    "dateOfBirth": "1986-01-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ARK",
    "firstName": "Arve",
    "lastName": "Kambe",
    "dateOfBirth": "1974-11-24T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GOK",
    "firstName": "Gorm",
    "lastName": "Kjernli",
    "dateOfBirth": "1981-12-30T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KKK",
    "firstName": "Kari Kjønaas",
    "lastName": "Kjos",
    "dateOfBirth": "1962-01-24T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MMK",
    "firstName": "Magnhild Meltveit",
    "lastName": "Kleppa",
    "dateOfBirth": "1948-11-11T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2012-10-06",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JKL",
    "firstName": "Jenny",
    "lastName": "Klinge",
    "dateOfBirth": "1975-11-27T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "UEK",
    "firstName": "Ulf Erik",
    "lastName": "Knudsen",
    "dateOfBirth": "1964-12-19T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KONTROLL",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LOKN",
    "firstName": "Lotte Grepp",
    "lastName": "Knutsen",
    "dateOfBirth": "1973-09-09T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TKK",
    "firstName": "Tove Karoline",
    "lastName": "Knutsen",
    "dateOfBirth": "1951-01-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MAKO",
    "firstName": "Martin",
    "lastName": "Kolberg",
    "dateOfBirth": "1949-02-23T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KONTROLL",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "OYK",
    "firstName": "Øyvind",
    "lastName": "Korsberg",
    "dateOfBirth": "1960-01-30T23:00:00Z",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "IVK",
    "firstName": "Ivar",
    "lastName": "Kristiansen",
    "dateOfBirth": "1956-02-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JFK",
    "firstName": "Janne Fardal",
    "lastName": "Kristoffersen",
    "dateOfBirth": "1970-11-07T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vest-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GJK",
    "firstName": "Gerd Janne",
    "lastName": "Kristoffersen",
    "dateOfBirth": "1952-11-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nord-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AHK",
    "firstName": "Aud Herbjørg",
    "lastName": "Kvalvik",
    "dateOfBirth": "1956-12-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HHL",
    "firstName": "Hallgeir H.",
    "lastName": "Langeland",
    "dateOfBirth": "1955-11-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      },
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KONTROLL",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BAAL",
    "firstName": "Bård",
    "lastName": "Langsåvold",
    "dateOfBirth": "1952-01-30T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nord-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KIL",
    "firstName": "Kjell Ivar",
    "lastName": "Larsen",
    "dateOfBirth": "1968-06-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vest-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SEL",
    "firstName": "Stein Erik",
    "lastName": "Lauvås",
    "dateOfBirth": "1965-05-02T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "UIL",
    "firstName": "Ulf",
    "lastName": "Leirstein",
    "dateOfBirth": "1973-06-29T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TALI",
    "firstName": "Tord",
    "lastName": "Lien",
    "dateOfBirth": "1975-09-09T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TOIL",
    "firstName": "Tone",
    "lastName": "Liljeroth",
    "dateOfBirth": "1975-03-18T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TL",
    "firstName": "Thor",
    "lastName": "Lillehovde",
    "dateOfBirth": "1948-04-02T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SYL",
    "firstName": "Sylvi",
    "lastName": "Listhaug",
    "dateOfBirth": "1977-12-24T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ALJ",
    "firstName": "Anna",
    "lastName": "Ljunggren",
    "dateOfBirth": "1984-06-12T22:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BLO",
    "firstName": "Bjørn",
    "lastName": "Lødemel",
    "dateOfBirth": "1958-08-18T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "POL",
    "firstName": "Per Olaf",
    "lastName": "Lundteigen",
    "dateOfBirth": "1953-04-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KONTROLL",
        "startDate": "2011-10-01",
        "endDate": null
      },
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": "2012-09-30"
      },
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2012-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ALYS",
    "firstName": "Audun",
    "lastName": "Lysbakken",
    "dateOfBirth": "1977-09-29T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EDM",
    "firstName": "Edvard",
    "lastName": "Mæland",
    "dateOfBirth": "1957-03-04T23:00:00Z",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HML",
    "firstName": "Hilde",
    "lastName": "Magnusson",
    "dateOfBirth": "1970-06-10T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KHAM",
    "firstName": "Khalid",
    "lastName": "Mahmood",
    "dateOfBirth": "1959-04-11T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SOM",
    "firstName": "Sonja",
    "lastName": "Mandt",
    "dateOfBirth": "1960-03-28T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vestfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MAM",
    "firstName": "Marianne",
    "lastName": "Marthinsen",
    "dateOfBirth": "1980-08-24T22:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": "2012-10-26"
      },
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2012-10-27",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BEM",
    "firstName": "Bente Stein",
    "lastName": "Mathisen",
    "dateOfBirth": "1956-01-31T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SME",
    "firstName": "Siri A.",
    "lastName": "Meling",
    "dateOfBirth": "1963-02-07T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TMI",
    "firstName": "Torgeir",
    "lastName": "Micaelsen",
    "dateOfBirth": "1979-05-19T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ASC",
    "firstName": "Åse",
    "lastName": "Michaelsen",
    "dateOfBirth": "1960-06-03T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vest-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "NIMJ",
    "firstName": "Nina",
    "lastName": "Mjøberg",
    "dateOfBirth": "1964-04-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "OBM",
    "firstName": "Ola Borten",
    "lastName": "Moe",
    "dateOfBirth": "1976-06-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "PEMY",
    "firstName": "Peter N.",
    "lastName": "Myhre",
    "dateOfBirth": "1954-11-28T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LMY",
    "firstName": "Lars",
    "lastName": "Myraune",
    "dateOfBirth": "1944-08-04T22:00:00Z",
    "dateOfDeath": null,
    "district": "Nord-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SMY",
    "firstName": "Sverre",
    "lastName": "Myrli",
    "dateOfBirth": "1971-08-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EIN",
    "firstName": "Eivind",
    "lastName": "Nævdal-Bolstad",
    "dateOfBirth": "1987-04-22T22:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LSN",
    "firstName": "Liv Signe",
    "lastName": "Navarsete",
    "dateOfBirth": "1958-10-22T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HTN",
    "firstName": "Harald T.",
    "lastName": "Nesvik",
    "dateOfBirth": "1966-05-03T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JAN",
    "firstName": "Jacob",
    "lastName": "Nødseth",
    "dateOfBirth": "1988-06-23T22:00:00Z",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "IRLN",
    "firstName": "Irene Lange",
    "lastName": "Nordahl",
    "dateOfBirth": "1968-02-10T23:00:00Z",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JSN",
    "firstName": "Janne Sjelmo",
    "lastName": "Nordås",
    "dateOfBirth": "1964-05-10T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TON",
    "firstName": "Tore",
    "lastName": "Nordtun",
    "dateOfBirth": "1949-09-29T22:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ELN",
    "firstName": "Elisabeth Røbekk",
    "lastName": "Nørve",
    "dateOfBirth": "1951-03-28T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MN",
    "firstName": "Marit",
    "lastName": "Nybakk",
    "dateOfBirth": "1947-02-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KONTROLL",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HIN",
    "firstName": "Hilde Anita",
    "lastName": "Nyvoll",
    "dateOfBirth": "1976-05-28T23:00:00Z",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JOD",
    "firstName": "Jon Øyvind",
    "lastName": "Odland",
    "dateOfBirth": "1954-05-28T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ANKO",
    "firstName": "Anne Karin",
    "lastName": "Olli",
    "dateOfBirth": "1964-12-20T23:00:00Z",
    "dateOfDeath": null,
    "district": "Finnmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "PO",
    "firstName": "Per Arne",
    "lastName": "Olsen",
    "dateOfBirth": "1961-02-20T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vestfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "WO",
    "firstName": "Wenche",
    "lastName": "Olsen",
    "dateOfBirth": "1965-11-29T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GUO",
    "firstName": "Gunn",
    "lastName": "Olsen",
    "dateOfBirth": "1952-09-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "IOL",
    "firstName": "Ingalill",
    "lastName": "Olsen",
    "dateOfBirth": "1955-12-14T23:00:00Z",
    "dateOfDeath": null,
    "district": "Finnmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KNO",
    "firstName": "Knut Magnus",
    "lastName": "Olsen",
    "dateOfBirth": "1954-05-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ODO",
    "firstName": "Odd",
    "lastName": "Omland",
    "dateOfBirth": "1956-01-28T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vest-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TO",
    "firstName": "Torfinn",
    "lastName": "Opheim",
    "dateOfBirth": "1961-04-11T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AOR",
    "firstName": "Anita",
    "lastName": "Orlund",
    "dateOfBirth": "1964-09-06T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HOR",
    "firstName": "Heidi",
    "lastName": "Ørnlo",
    "dateOfBirth": "1957-11-29T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vestfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "WAP",
    "firstName": "Willy",
    "lastName": "Pedersen",
    "dateOfBirth": "1981-10-31T23:00:00Z",
    "dateOfDeath": null,
    "district": "Finnmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HPED",
    "firstName": "Helga",
    "lastName": "Pedersen",
    "dateOfBirth": "1973-01-12T23:00:00Z",
    "dateOfDeath": null,
    "district": "Finnmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TAGP",
    "firstName": "Tage",
    "lastName": "Pettersen",
    "dateOfBirth": "1972-07-24T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "GP",
    "firstName": "Geir",
    "lastName": "Pollestad",
    "dateOfBirth": "1978-08-12T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AR",
    "firstName": "Afshan",
    "lastName": "Rafiq",
    "dateOfBirth": "1975-02-24T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ABIR",
    "firstName": "Abid Q.",
    "lastName": "Raja",
    "dateOfBirth": "1975-11-04T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "V",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "CNR",
    "firstName": "Christina Nilsson",
    "lastName": "Ramsøy",
    "dateOfBirth": "1986-11-03T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nord-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LRE",
    "firstName": "Laila Marie",
    "lastName": "Reiertsen",
    "dateOfBirth": "1960-10-18T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SR",
    "firstName": "Steinar",
    "lastName": "Reiten",
    "dateOfBirth": "1963-05-09T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JRI",
    "firstName": "Johannes",
    "lastName": "Rindal",
    "dateOfBirth": "1984-02-21T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SOR",
    "firstName": "Solveig",
    "lastName": "Rindhølen",
    "dateOfBirth": "1973-07-29T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TRR",
    "firstName": "Trond",
    "lastName": "Røed",
    "dateOfBirth": "1959-12-10T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MAGR",
    "firstName": "Magne",
    "lastName": "Rommetveit",
    "dateOfBirth": "1956-04-26T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KJR",
    "firstName": "Kjell Ingolf",
    "lastName": "Ropstad",
    "dateOfBirth": "1985-05-31T22:00:00Z",
    "dateOfDeath": null,
    "district": "Aust-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": "2012-09-30"
      },
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2012-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TR",
    "firstName": "Torstein",
    "lastName": "Rudihagen",
    "dateOfBirth": "1951-08-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "FIR",
    "firstName": "Filip",
    "lastName": "Rygg",
    "dateOfBirth": "1983-10-18T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JHR",
    "firstName": "Jørund",
    "lastName": "Rytman",
    "dateOfBirth": "1977-05-03T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "PES",
    "firstName": "Per",
    "lastName": "Sandberg",
    "dateOfBirth": "1960-02-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ESAN",
    "firstName": "Erling",
    "lastName": "Sande",
    "dateOfBirth": "1978-11-07T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JTS",
    "firstName": "Jan Tore",
    "lastName": "Sanner",
    "dateOfBirth": "1965-05-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ISC",
    "firstName": "Ingjerd",
    "lastName": "Schou",
    "dateOfBirth": "1955-01-19T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KSIM",
    "firstName": "Kåre",
    "lastName": "Simensen",
    "dateOfBirth": "1955-08-29T23:00:00Z",
    "dateOfDeath": null,
    "district": "Finnmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EIRS",
    "firstName": "Eirik",
    "lastName": "Sivertsen",
    "dateOfBirth": "1971-03-16T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SONS",
    "firstName": "Sonja Irene",
    "lastName": "Sjøli",
    "dateOfBirth": "1949-06-05T22:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KSJ",
    "firstName": "Knut",
    "lastName": "Sjømæling",
    "dateOfBirth": "1960-07-11T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SSK",
    "firstName": "Siv Aida Rui",
    "lastName": "Skattem",
    "dateOfBirth": "1970-04-08T23:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ENS",
    "firstName": "Endre",
    "lastName": "Skjervø",
    "dateOfBirth": "1973-07-23T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nord-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ESKO",
    "firstName": "Elizabeth",
    "lastName": "Skogrand",
    "dateOfBirth": "1970-02-26T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ELIS",
    "firstName": "Eli",
    "lastName": "Skoland",
    "dateOfBirth": "1958-05-10T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MSKR",
    "firstName": "Magnus",
    "lastName": "Skretting",
    "dateOfBirth": "1958-07-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HSK",
    "firstName": "Henning",
    "lastName": "Skumsvoll",
    "dateOfBirth": "1947-03-14T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vest-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ES",
    "firstName": "Erna",
    "lastName": "Solberg",
    "dateOfBirth": "1961-02-23T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TTS",
    "firstName": "Torstein Tvedt",
    "lastName": "Solberg",
    "dateOfBirth": "1985-03-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BVS",
    "firstName": "Bård Vegar",
    "lastName": "Solhjell",
    "dateOfBirth": "1971-12-21T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JHS",
    "firstName": "Jonni Helge",
    "lastName": "Solsvik",
    "dateOfBirth": "1952-02-26T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KETS",
    "firstName": "Ketil",
    "lastName": "Solvik-Olsen",
    "dateOfBirth": "1972-02-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TMS",
    "firstName": "Tone Merete",
    "lastName": "Sønsterud",
    "dateOfBirth": "1959-05-16T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "IME",
    "firstName": "Ine M. Eriksen",
    "lastName": "Søreide",
    "dateOfBirth": "1976-05-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HEIS",
    "firstName": "Heidi",
    "lastName": "Sørensen",
    "dateOfBirth": "1970-02-13T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AESO",
    "firstName": "Arne",
    "lastName": "Sortevik",
    "dateOfBirth": "1947-03-11T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "TRANSKOM",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AGES",
    "firstName": "Åge",
    "lastName": "Starheim",
    "dateOfBirth": "1946-05-22T22:00:00Z",
    "dateOfDeath": null,
    "district": "Sogn og Fjordane",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AAST",
    "firstName": "Arild",
    "lastName": "Stokkan-Grande",
    "dateOfBirth": "1978-04-04T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nord-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JES",
    "firstName": "Jens",
    "lastName": "Stoltenberg",
    "dateOfBirth": "1959-03-15T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KNUS",
    "firstName": "Knut",
    "lastName": "Storberget",
    "dateOfBirth": "1964-10-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "FMS",
    "firstName": "Morten",
    "lastName": "Stordalen",
    "dateOfBirth": "1968-10-04T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vestfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JGS",
    "firstName": "Jonas Gahr",
    "lastName": "Støre",
    "dateOfBirth": "1960-08-24T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KSTO",
    "firstName": "Kari",
    "lastName": "Storstrand",
    "dateOfBirth": "1969-03-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TAS",
    "firstName": "Tor-Arne",
    "lastName": "Strøm",
    "dateOfBirth": "1952-05-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ANS",
    "firstName": "Anne-Grete",
    "lastName": "Strøm-Erichsen",
    "dateOfBirth": "1949-10-20T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "FS",
    "firstName": "Frøydis Elisabeth",
    "lastName": "Sund",
    "dateOfBirth": "1980-05-17T22:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EKS",
    "firstName": "Eirin",
    "lastName": "Sund",
    "dateOfBirth": "1967-04-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ENERGI",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KSV",
    "firstName": "Kjell Arvid",
    "lastName": "Svendsen",
    "dateOfBirth": "1953-08-26T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KES",
    "firstName": "Kenneth",
    "lastName": "Svendsen",
    "dateOfBirth": "1954-08-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HOSY",
    "firstName": "Hans Olav",
    "lastName": "Syversen",
    "dateOfBirth": "1966-11-24T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HTA",
    "firstName": "Hadia",
    "lastName": "Tajik",
    "dateOfBirth": "1983-07-17T22:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": "2012-10-05"
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "DOT",
    "firstName": "Dag Ole",
    "lastName": "Teigen",
    "dateOfBirth": "1982-08-09T22:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BT",
    "firstName": "Borghild",
    "lastName": "Tenden",
    "dateOfBirth": "1951-06-22T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "V",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "MIT",
    "firstName": "Michael",
    "lastName": "Tetzschner",
    "dateOfBirth": "1954-02-08T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KOMMFORV",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "OLET",
    "firstName": "Olemic",
    "lastName": "Thommessen",
    "dateOfBirth": "1956-04-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "IBTH",
    "firstName": "Ib",
    "lastName": "Thomsen",
    "dateOfBirth": "1961-10-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Akershus",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FAMKULT",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "IMT",
    "firstName": "Inga Marte",
    "lastName": "Thorkildsen",
    "dateOfBirth": "1976-07-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vestfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LAT",
    "firstName": "Laila",
    "lastName": "Thorsen",
    "dateOfBirth": "1967-06-25T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "BTH",
    "firstName": "Bente",
    "lastName": "Thorsen",
    "dateOfBirth": "1958-10-30T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "JT",
    "firstName": "John",
    "lastName": "Thune",
    "dateOfBirth": "1948-02-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HLT",
    "firstName": "Hanne",
    "lastName": "Thürmer",
    "dateOfBirth": "1960-09-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "KrF",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KJT",
    "firstName": "Kjersti",
    "lastName": "Toppe",
    "dateOfBirth": "1967-10-19T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "HELSEOMS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KPT",
    "firstName": "Knut Petter",
    "lastName": "Torgersen",
    "dateOfBirth": "1955-09-06T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TOVT",
    "firstName": "Tove-Lise",
    "lastName": "Torve",
    "dateOfBirth": "1964-06-07T23:00:00Z",
    "dateOfDeath": null,
    "district": "Møre og Romsdal",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TOT",
    "firstName": "Torgeir",
    "lastName": "Trældal",
    "dateOfBirth": "1965-01-01T23:00:00Z",
    "dateOfDeath": null,
    "district": "Nordland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "NÆRING",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ATR",
    "firstName": "Anette",
    "lastName": "Trettebergstuen",
    "dateOfBirth": "1981-05-24T22:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "ARBSOS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "CT",
    "firstName": "Christian",
    "lastName": "Tybring-Gjedde",
    "dateOfBirth": "1963-08-07T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "FINANS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TSU",
    "firstName": "Tor Sigbjørn",
    "lastName": "Utsogn",
    "dateOfBirth": "1974-03-31T23:00:00Z",
    "dateOfDeath": null,
    "district": "Vest-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LVA",
    "firstName": "Lene",
    "lastName": "Vågslid",
    "dateOfBirth": "1986-03-16T23:00:00Z",
    "dateOfDeath": null,
    "district": "Telemark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "OVA",
    "firstName": "Øyvind",
    "lastName": "Vaksdal",
    "dateOfBirth": "1955-10-18T23:00:00Z",
    "dateOfDeath": null,
    "district": "Rogaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KONTROLL",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "SNV",
    "firstName": "Snorre Serigstad",
    "lastName": "Valen",
    "dateOfBirth": "1984-09-15T22:00:00Z",
    "dateOfDeath": null,
    "district": "Sør-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "SV",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TORV",
    "firstName": "Torill",
    "lastName": "Vebenstad",
    "dateOfBirth": "1955-01-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TMV",
    "firstName": "Trygve Slagsvold",
    "lastName": "Vedum",
    "dateOfBirth": "1978-11-30T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hedmark",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "LVE",
    "firstName": "Line",
    "lastName": "Vennesland",
    "dateOfBirth": "1985-02-05T23:00:00Z",
    "dateOfDeath": null,
    "district": "Aust-Agder",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "HEW",
    "firstName": "Henning",
    "lastName": "Warloe",
    "dateOfBirth": "1961-03-23T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "AWE",
    "firstName": "Anders B.",
    "lastName": "Werp",
    "dateOfBirth": "1961-12-15T23:00:00Z",
    "dateOfDeath": null,
    "district": "Buskerud",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "JUSTIS",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EW",
    "firstName": "Erlend",
    "lastName": "Wiborg",
    "dateOfBirth": "1984-01-19T23:00:00Z",
    "dateOfDeath": null,
    "district": "Østfold",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "TRUW",
    "firstName": "Truls",
    "lastName": "Wickholm",
    "dateOfBirth": "1978-10-14T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "ATW",
    "firstName": "Anne Tingelstad",
    "lastName": "Wøien",
    "dateOfBirth": "1965-06-17T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oppland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "Sp",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KSW",
    "firstName": "Karin S.",
    "lastName": "Woldseth",
    "dateOfBirth": "1954-08-08T23:00:00Z",
    "dateOfDeath": null,
    "district": "Hordaland",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "UFK",
        "startDate": "2011-10-01",
        "endDate": null
      }
    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "KY",
    "firstName": "Karin",
    "lastName": "Yrvin",
    "dateOfBirth": "1970-06-19T23:00:00Z",
    "dateOfDeath": null,
    "district": "Oslo",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "A",
        "startDate": "2010-10-01",
        "endDate": "2011-09-30"
      }
    ],
    "committees": [
      {
        "kind": "hdo#committeeMembership",
        "externalId": "KIRKE",
        "startDate": "2012-10-06",
        "endDate": null
      }
    ]
  }
]
