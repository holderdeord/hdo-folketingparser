#!/bin/bash

if [[ "$#" -ne 1  ]]; then
    echo "USAGE: ${0} denormalized-votes.csv"
    exit 1
fi

function abs_path {
    (cd "$(dirname '$1')" &>/dev/null && printf "%s/%s" "$(pwd)" "${1##*/}")
}

votes_csv="$(abs_path $1)"

psql postgres <<EOF
  DROP DATABASE IF EXISTS votes;
  CREATE DATABASE votes;
  \connect votes;
 
  CREATE TABLE votes (
       person_id integer,
       person_initials character varying(255),
       person_first_name character varying(255),
       person_last_name character varying(255),
       person_position_no character varying(255),
       person_position_en character varying(255),
       person_party_id integer,
       person_party_name character varying(255),
       person_constituency_code character varying(255),
       person_constituency_name character varying(255),

       vote_id character varying(30),
       vote_period_id integer,
       vote_party_id integer,
       vote_party_name character varying(255),
       vote_session_name character varying(255),
       vote_chamber_name character varying(255),
       vote_result character varying(255),
       vote_number character varying(255),
       vote_seat_number character varying(255),
       vote_map integer,
       vote_issue integer
  );

  COPY votes FROM '${votes_csv}' DELIMITER ',' CSV HEADER QUOTE '"' NULL '';
EOF
