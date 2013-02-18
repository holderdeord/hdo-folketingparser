#!/usr/bin/env ruby
# encoding: UTF-8
require 'json'
require 'time'
require 'set'
require 'active_support/core_ext/object/try'

class VoteFileReader
  def initialize(filename, rep_reader)
    @file = File.new(filename)
    @rep_reader = rep_reader
  end

  def vote_file_data
    read_votes unless @votes
    @vote_data ||= @votes.reduce({}) do |hash, (id, lines)|
      hash[id] = {
        counts:          counts_for(lines),
        representatives: reps_for(lines) # join with politikerarkiv, hdo-site db, etc.
      }
      
      hash[id].merge!({
        enacted:         hash[id][:counts][:for] > hash[id][:counts][:against]
        })

      hash
    end
  end

  private
  
  def read_votes
    @votes = Hash.new
    @file.lines.each do |line|
      (num, periode, ses, sal, kart, sak, votnr,
        votering, setenr, person, parti) = line.split(",").map(&:strip)
      vote_id = "#{kart}-#{sak}-#{votnr}"
      (@votes[vote_id] ||= []) << line
    end
    @votes
  end

  def counts_for(lines)
    lines.reduce({for:0, against:0}) do |counts, line|
      (num, periode, ses, sal, kart, sak, votnr,
        votering, setenr, person, parti) = line.split(",").map(&:strip)
      if votering == '1'
        counts[:for] += 1
      else
        counts[:against] += 1
      end

      counts
    end
  end

  def reps_for(lines)
    lines.map do |line|
      (num, periode, ses, sal, kart, sak, votnr,
        votering, setenr, person, parti) = line.split(",").map(&:strip)
      @rep_reader.find_rep_by_number(person, setenr, parti).merge({
        "voteResult" => votering == '1' ? 'for' : 'against'
        })
    end
  end
end

class SaksOpplysningFileReader
  def initialize(filename)
    @file = File.new(filename)
  end

  def saksopplysning_data
    @votes = Hash.new
    @file.lines.each do |line|
      (periode, dato, tid, ses, sal, kart,
        sak, votnr, typsak, vottyp, komite,
        saksreferanse, saksregister, emne,
        president, presidentparti,
        internkommentar, lenke) = line.split(",").map(&:strip)
      vote_id = "#{kart}-#{sak}-#{votnr}"
      @votes[vote_id] = {
        timestamp: timestamp_from(dato, tid),
        subject:   saksreferanse,
        kartnr:    kart,
        saknr:     sak,
        votnr:     votnr
      }
    end
    @votes
  end

  private
  def timestamp_from(date, time)
    Time.parse("#{date} #{time}")
  end
end

class PolitikerarkivFileReader
  def initialize(politikerarkiv_file, hdo_reps_file)
    @politikerarkiv_file = File.new(politikerarkiv_file)
    @hdo_reps            = JSON.parse(File.read(hdo_reps_file))
    @hdo_reps <<           JSON.parse(DATA.read)
    @hdo_reps.flatten!
  end

  def find_rep_by_number(person_id, setenr, parti_id)
    @reps ||= @politikerarkiv_file.lines.reduce({}) do |reps, line|
      (person, personlegid, initialer, fornavn, navn, stilling, 
        engstilling, parti, periode, ny_valkrinskode, valkrinsnamn, 
        repnr, supnr, eksternkommentar, internkommentar, min_reg, 
        min_reg_hv) = line.split(",").map(&:strip)
      reps[person] = find_rep(initialer, fornavn, navn)

      reps
    end

    # raise @reps[person_id].inspect if person_id == '2338'
    (@reps[person_id] || ghost_rep(person_id, parti_id)).tap do |rep|
      # raise rep.inspect
      if !rep['touched'] && needs_party_membership(rep)
        rep['parties'] << {
          "kind"       => "hdo#partyMembership",
          "externalId" => party(parti_id),
          "startDate"  => "2009-10-1",
          "endDate"    => "2010-9-30"
        }
        rep['parties'].uniq!
        rep['touched'] = true
      end
    end
  end

  def needs_party_membership(rep)
    @_date ||= Time.parse('2009-10-1')
    !rep['parties'].find do |party_membership|
      Time.parse(party_membership['startDate']) <= @_date && (party_membership['endDate'].nil? || Time.parse(party_membership['endDate']) >= @_date)
    end
  end

  def find_missing_reps_verify
    missing = Set.new

    @politikerarkiv_file.lines.each do |line|
      (person, personlegid, initialer, fornavn, navn, stilling, 
        engstilling, parti, periode, ny_valkrinskode, valkrinsnamn, 
        repnr, supnr, eksternkommentar, internkommentar, min_reg, 
        min_reg_hv) = line.split(",").map(&:strip)
        
        missing << [initialer, fornavn, navn] unless find_rep(initialer, fornavn, navn)
    end

    missing
  end

  def ghosts
    @ghosts
  end

  private

  def party(id)
    {
      '11' =>  'RV',
      '14' =>  'SV',
      '21' =>  'A',
      '23' =>  'Folkeaksjonen Framtid for Finnmark',
      '24' =>  'Tverrpolitisk Folkevalgte',
      '31' =>  'V',
      '41' =>  'Sp',
      '51' =>  'KrF',
      '71' =>  'H',
      '81' =>  'FrP',
      '98' =>  'Uavhengige',
      '238' => 'Kystpartiet'
    }[id]
  end

  def ghost_rep(id, party)
    rescued_ghost = rescue_ghost(id.to_i)
    return rescued_ghost if rescued_ghost
    raise "could not find rep with id #{id} #{id.to_i}"

    (@ghosts ||= Set.new) << id
    {
      "kind"           => "hdo#representative",
      "externalId"     => id,
      "firstName"      => "-",
      "lastName"       => "-",
      "dateOfBirth"    => "-",
      "dateOfDeath"    => "-",
      "district"       => "-",
      "parties"        => [
        {
          "kind"       => "hdo#partyMembership",
          "externalId" => party(party),
          "startDate"  => "2009-10-1",
          "endDate"    => "2010-9-30"
        }
      ],
      "committees"     => [

      ]
    }
  end

  def rescue_ghost(id)
    @ghost_map ||= {
      31442 => 'iag',
      31391 => 'fbj',
      31426 => 'hew',
      31630 => 'asc',
      31348 => 'blo',
      31580 => 'shar',
      31519 => 'meth',
      31328 => 'ark',
      31516 => 'jong',
      31507 => 'lmy',
      31301 => 'hped',
      31623 => 'tovt',
      31598 => 'sub',
      30745 => 'bvs',
      31449 => 'wap',
      31296 => 'tl',
      31478 => 'kjt',
      31372 => 'eirs',
      31318 => 'aleh',
      31511 => 'magr',
      31317 => 'aksh',
      31357 => 'efu',
      31640 => 'wo',
      31403 => 'einh',
      31589 => 'snv',
      31490 => 'ksim',
      31416 => 'hakh',
      31327 => 'areh',
      30956 => 'dh',
      31596 => 'strh',
      31440 => 'hta',
      31298 => 'irln',
      31402 => 'gjb',
      31525 => 'mit',
      30025 => 'lbt'
    }
    @hdo_reps.find do |hdo_rep|
      hdo_rep['externalId'].downcase == @ghost_map[id]
    end
  end

  def find_rep(initials, first_name, last_name)
    @hdo_reps.find do |hdo_rep|
      hdo_rep['externalId'] == initials && hdo_rep['firstName'] == first_name && hdo_rep['lastName'] == last_name
    end
  end
end

class HdoVoteCollator
  def initialize(saksopplysninger, votes, propositions = {}, issue_map = {})
    @saksopplysninger = saksopplysninger
    @votes            = votes
    @propositions     = propositions
    @issue_map        = issue_map
  end

  def votes
    @saksopplysninger.map do |sks_id, sak|
      votes = @votes[sks_id]
      next unless votes
      {
        kind:            'hdo#vote',
        externalId:      "#{sak[:timestamp]}#{sak[:votnr]}",
        externalIssueId: @issue_map[[sak[:kartnr], sak[:saknr], sak[:timestamp].strftime('%Y%m%d')]].try(:join, ",") || "",
        counts:          votes[:counts],
        personal:        true,
        enacted:         votes[:enacted],
        subject:         sak[:subject][0..254],
        method:          "ikke_spesifisert",
        resultType:      "ikke_spesifisert",
        time:            sak[:timestamp].iso8601,
        representatives: votes[:representatives],
        propositions:    @propositions.delete("#{sak[:timestamp].to_date.to_s}:#{sak[:kartnr]}:#{sak[:saknr]}") || []
      }
    end
  end

  def remaining_props
    @propositions
  end
end

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

if __FILE__ == $0
  abort "USAGE: #{$PROGRAM_NAME} votes_file issue_file hdo_reps_file politikerarkiv_file props_filr" unless ARGV.count == 6
  politikerarkiv_file_reader = PolitikerarkivFileReader.new(ARGV[2], ARGV[3])

  vote_file_reader = VoteFileReader.new(ARGV.first, politikerarkiv_file_reader)
  votes = vote_file_reader.vote_file_data
  # abort "ghosts(#{politikerarkiv_file_reader.ghosts.count}): #{politikerarkiv_file_reader.ghosts.to_a}" if politikerarkiv_file_reader.ghosts

  saksopplysning_file_reader = SaksOpplysningFileReader.new(ARGV[1])
  saksopplysninger = saksopplysning_file_reader.saksopplysning_data

  props = JSON.parse(File.read(ARGV[4]))

  issue_map = KartIssueMapper.new(ARGV[5]).issue_map

  personal_votes_collator = HdoVoteCollator.new(saksopplysninger, votes, props, issue_map)
  personal_votes = personal_votes_collator.votes
  puts JSON.pretty_generate personal_votes

  # unused_props = personal_votes_collator.remaining_props
  # puts JSON.pretty_generate unused_props

end

__END__
[
  {
    "kind": "hdo#representative",
    "externalId": "KEG",
    "firstName": "Kent",
    "lastName": "Gudmundsen",
    "dateOfBirth": "1978-3-5",
    "dateOfDeath": null,
    "district": "Troms",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "H",
        "startDate": "2009-10-01",
        "endDate": "2010-09-30"
      }
    ],
    "committees": [

    ]
  },
  {
    "kind": "hdo#representative",
    "externalId": "EFU",
    "firstName": "Erlend",
    "lastName": "Fuglum",
    "dateOfBirth": "1978-3-13",
    "dateOfDeath": null,
    "district": "Nord-Trøndelag",
    "parties": [
      {
        "kind": "hdo#partyMembership",
        "externalId": "FrP",
        "startDate": "2009-10-01",
        "endDate": "2010-09-30"
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
        "startDate": "2009-10-01",
        "endDate": "2010-09-30"
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
        "startDate": "2009-10-01",
        "endDate": "2010-09-30"
      }
    ],
    "committees": [

    ]
  }
]