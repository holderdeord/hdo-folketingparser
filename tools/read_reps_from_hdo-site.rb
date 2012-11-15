#!/usr/bin/env ruby
require File.expand_path('../../../hdo-site/config/boot',  __FILE__)
require File.expand_path('../../../hdo-site/config/application',  __FILE__)
require File.expand_path('../../../hdo-site/config/environment',  __FILE__)

def party_memberships_for(rep)
  party_memberships = PartyMembership.includes(:party).find_all_by_representative_id(rep.id)
  party_memberships.map do |membership|
    {
      kind:       'hdo#partyMembership',
      externalId: membership.party.external_id,
      startDate:  membership.start_date.iso8601,
      endDate:    membership.end_date ? membership.end_date.iso8601 : nil
    }
  end
end

def committee_memberships_for(rep)
  party_memberships = CommitteeMembership.includes(:committee).find_all_by_representative_id(rep.id)
  party_memberships.map do |membership|
    {
      kind:       'hdo#committeeMembership',
      externalId: membership.committee.external_id,
      startDate:  membership.start_date.iso8601,
      endDate:    membership.end_date ? membership.end_date.iso8601 : nil
    }
  end
end

reps = Representative.all.map do |rep|
  {
    kind:        'hdo#representative',
    externalId:  rep.external_id,
    firstName:   rep.first_name,
    lastName:    rep.last_name,
    dateOfBirth: rep.date_of_birth,
    dateOfDeath: rep.date_of_death,
    district:    rep.district.name,
    parties:     party_memberships_for(rep),
    committees:  committee_memberships_for(rep)
  }
end

puts JSON.pretty_generate(reps)