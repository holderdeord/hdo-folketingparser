#!/bin/bash

#
# automate the process from 154.md
# 

set -e
set -x

ROOT=`dirname $0`/..

./tools/convert-nsd-to-json.rb rawdata/Fra\ NSD/154.csv rawdata/Fra\ NSD/154_saksopplysninger.csv rawdata/Fra\ NSD/154_politikerarkiv_manually_augmented.csv hdo_site_reps.json rawdata/forslag-vedtak-2009-2011/propositions-2009-2010.json rawdata/saksid/Dagsorden\ 20009-2010-tabseparated.txt > "${ROOT}/154.json"

cd $ROOT/rawdata/forslag-vedtak-2009-2011
./vedtak_converter.rb > vedtak2009.json
cd -

tools/make_non_personal_votes_154.rb > npv154.json
ruby -rjson -e "puts JSON.generate (JSON.parse(File.read('./154.json')) + (JSON.parse(File.read('./npv154.json'))))" > votes-2009-2010.json


