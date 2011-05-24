INSERT INTO person_ref (person_id, type, ref)
  SELECT person_id, 'no.wikipedia.org', 'Freddy_De_Ruiter'
     FROM person_ref WHERE TYPE = 'stortinget-perid' and ref= 'FR';

INSERT INTO person_ref (person_id, type, ref)
  SELECT person_id, 'nsd-polsys-id', '2170'
     FROM person_ref WHERE TYPE = 'stortinget-perid' and ref= 'FR';

UPDATE division SET heading_id = 48061, yes_count = 58, no_count = 38
        WHERE when_divided = '2011-03-21T18:26:46';

UPDATE division SET heading_id = 48650, yes_count = 89, no_count = 80
        WHERE when_divided = '2011-04-04T21:44:54';
UPDATE division SET heading_id = 48650, yes_count = 89, no_count = 80
        WHERE when_divided = '2011-04-04T21:45:27';
