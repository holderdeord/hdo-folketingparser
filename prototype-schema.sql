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

CREATE TABLE division (
  id int PRIMARY KEY NOT NULL,
  description text,
  heading_id int,
  when_divided timedate NOT NULL,
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
  vote NOT NULL REFERENCES vote_types(vote)
);
