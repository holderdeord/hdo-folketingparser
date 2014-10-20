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

       vote_id character varying(30) primary key not null,
       vote_period_id integer not null,
       vote_party_id integer not null,
       vote_party_name character varying(255) not null,
       vote_session_name character varying(255),
       vote_chamber_name character varying(255),
       vote_result character varying(255) not null,
       vote_map integer not null,
       vote_issue integer not null,
       vote_number integer not null,
       vote_seat_number character varying(255),

       issue_date character varying(255),
       issue_time character varying(255),
       issue_type integer,
       issue_type_text text,
       issue_vote_type integer,
       issue_vote_type_text text,
       issue_committee integer,
       issue_committee_name character varying(255),
       issue_reference text,
       issue_register character varying(255),
       issue_subject integer,
       issue_subject_name character varying(255),
       issue_president integer,
       issue_president_initials character varying(10),
       issue_president_party_id integer,
       issue_president_party_name character varying(255),
       issue_internal_comment text,
       issue_minutes_url character varying(255)
  );

  COPY votes FROM '${votes_csv}' DELIMITER ',' CSV HEADER QUOTE '"' NULL '';

  CREATE INDEX index_votes_on_vote_session_name ON votes (vote_session_name);
  CREATE INDEX index_votes_on_issue_and_vote_result_and_vote_party_name ON votes (vote_result, vote_session_name, vote_map, vote_issue, vote_party_name)
EOF
