#!/usr/bin/env ruby
# encoding: utf-8

=begin

  Hei!
 
  Grunnen til at dette ikke var med var at annengangsvoteringer ble hoppet over. Det var litt inkonsekvent bruk av voteringsanlegget i forhold til annengangsvoteringer denne første sesjonen med det nye anlegget, men denne gangen skulle det vært med.
  Jeg har tatt ut avstemningen som da gjelder Forslag nr. 1 pva FrP, SV, Sp, KrF og V satt opp som sak nr 7 med voternigstidspunkt 2011-04-11 13:56:52.350
  Jeg gjør oppmerksom på at stemmetallene er 46 FOR og 59 Mot. Dette går også fram fra referatet dersom man leser om avstemningen. Bodil Tenden gjorde oppmerksom på at hun hadde stemt feil og fikk korrigert dette.
 
  Mvh Sissel
  
=end



require 'json'
require 'csv'
require 'pp'
require 'time'
require 'digest/md5'
require 'pry'

path     = File.expand_path("../../rawdata/stortinget-voteringer-155/forslag-nr-1-pva-frp-sv-sp-krf-og-v.csv", __FILE__)
results  = CSV.parse(File.read(path).sub("\xEF\xBB\xBF", ''), col_sep: ';')
time     = Time.parse("2011-04-11 13:56:52.350")
hdo_reps = JSON.parse(File.read(File.expand_path("../../hdo_site_reps.json", __FILE__))) 
reps     = hdo_reps.each_with_object({}) { |rep, obj| obj[rep['externalId']] = rep }
reps.default_proc = lambda { |hash, key| hash[key] = alts.fetch(key) }

trans = {
  'J' => 'for',
  'N' => 'against',
  ' ' => 'absent'
}

vote = {
  "kind" => "hdo#vote",
  "externalId" => "2011-04-11 13:56:52.350n",
  "externalIssueId" => "48717",
  "counts" => {
    "for" => 46,
    "against" => 59,
    "absent" => 169 - 46 - 59
  },
  "personal" => true,
  "enacted" => false,
  "subject" => "Forslag fra Bård Hoksrud på vegne av Fremskrittspartiet, Sosialistisk Venstreparti, Senterpartiet, Kristelig Folkeparti og Venstre",
  "method" => "ikke_spesifisert",
  "resultType" => "ikke_spesifisert",
  "time" => time,
  "representatives" => results.map { |rep_id, result| reps.fetch(rep_id).merge('voteResult' => trans.fetch(result)) },
  "propositions" => [
    {
      "kind" => "hdo#proposition",
      "onBehalfOf" => "Fremskrittspartiet, Sosialistisk Venstreparti, Senterpartiet, Kristelig Folkeparti og Venstre",
      "externalId" => Digest::MD5.hexdigest(time.strftime("%Y-%m-%d") + "Lovvedtaket bifalles ikke. Anmerkning: Lovforslaget bør henlegges."),
      "description" => "Forslag på vegne av Fremskrittspartiet, Sosialistisk Venstreparti. Senterpartiet, Kristelig Folkeparti og Venstre",
      "body" => "Lovvedtaket bifalles ikke. Anmerkning: Lovforslaget bør henlegges.",
    }
  ]
}

puts JSON.pretty_generate(vote)
