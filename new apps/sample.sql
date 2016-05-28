------------------------------------------------------------
-- SAMPLE (DUMMY) APPLICATION
------------------------------------------------------------

/* This doesn't do anything interesting, just create a table */
DROP TABLE IF EXISTS sample CASCADE;
CREATE UNLOGGED TABLE sample (
       id  integer PRIMARY KEY
);


/* Create a dummy view from the table */
DROP VIEW IF EXISTS sample_view;
CREATE OR REPLACE VIEW sample_view AS (
       SELECT id
       FROM sample
);


/* ---REQUIRED VIEW--- violation for sample application's constraints.
 * Dummy constraint: no flows with source node id = 1
 */
CREATE OR REPLACE VIEW sample_violation AS (
       SELECT fid
       FROM rm
       WHERE src = 1;
);


/* ---REQUIRED RULE--- repair violations by removing flow that
 * violates constraint
 */
CREATE OR REPLACE RULE FW_repair AS
       ON DELETE TO FW_violation
       DO INSTEAD
          DELETE FROM rm WHERE fid = OLD.fid;
