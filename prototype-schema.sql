--  member_of_parlament
CREATE TABLE person (
  id int PRIMARY KEY NOT NULL,
  first_name text,
  last_name text
);

CREATE TABLE person_ref (
  person_id int NOT NULL REFERENCES person(id),
  type text, -- (stortinget, polsys, wikipedia)
  ref text
);

CREATE TABLE office_entered_reason_type (
  reason text
);
INSERT INTO office_entered_reason_type VALUES ('unknown');
INSERT INTO office_entered_reason_type VALUES ('general_election');
INSERT INTO office_entered_reason_type VALUES ('by_election');
INSERT INTO office_entered_reason_type VALUES ('changed_party');
INSERT INTO office_entered_reason_type VALUES ('reinstated');

CREATE TABLE office_left_reason_type (
  reason text
);
INSERT INTO office_left_reason_type VALUES ('unknown');
INSERT INTO office_left_reason_type VALUES ('still_in_office');
INSERT INTO office_left_reason_type VALUES ('general_election');
INSERT INTO office_left_reason_type VALUES ('general_election_standing');
INSERT INTO office_left_reason_type VALUES ('general_election_not_standing');
INSERT INTO office_left_reason_type VALUES ('changed_party');
INSERT INTO office_left_reason_type VALUES ('died');
INSERT INTO office_left_reason_type VALUES ('declared_void');
INSERT INTO office_left_reason_type VALUES ('resigned');
INSERT INTO office_left_reason_type VALUES ('disqualified');
INSERT INTO office_left_reason_type VALUES ('became_peer');

CREATE TABLE office_holder (
  person_id int NOT NULL REFERENCES person(id),
  party varchar(100),
  office_name varchar(100) NOT NULL,
  constituency varchar(100),

  entered_house date NOT NULL DEFAULT '1000-01-01',
  left_house date NOT NULL DEFAULT '9999-12-31',
  entered_reason NOT NULL REFERENCES office_entered_reason_type(reason)
                 DEFAULT 'unknown',
  left_reason NOT NULL REFERENCES office_left_reason_type(reason)
                 DEFAULT 'unknown'
);

CREATE TABLE division (
  id int PRIMARY KEY NOT NULL,
  description text,
  heading_id int,
  when_divided timedate NOT NULL,
  session_num int,
  map_num int,
  topic_num int,
  yes_count int NOT NULL,
  no_count int NOT NULL
);

CREATE TABLE vote_types (
       vote text
);
INSERT INTO vote_types values ('yes');
INSERT INTO vote_types values ('no');
INSERT INTO vote_types values ('absent');

CREATE TABLE vote (
  division_id int NOT NULL REFERENCES division(id),
  person_id int NOT NULL REFERENCES person(id),
  vote NOT NULL REFERENCES vote_types(vote),
  party varchar(100)
);
