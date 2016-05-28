------------------------------------------------------------
-- STATEFUL FIREWALL
------------------------------------------------------------

/* Flow whitelist */
DROP TABLE IF EXISTS FW0_policy_acl CASCADE;
CREATE UNLOGGED TABLE FW0_policy_acl (
       end1           integer,
       end2           integer,
       allow          integer,
       PRIMARY key (end1, end2)
);
CREATE INDEX ON FW0_policy_acl (end1,end2);

/* Node whitelist */
DROP TABLE IF EXISTS FW0_policy_user CASCADE;
CREATE UNLOGGED TABLE FW0_policy_user (
       uid            integer
);

/* If flow source is in whitelist, allow and add to flow whitelist */
CREATE OR REPLACE RULE FW01 AS
       ON INSERT TO rm
       WHERE ((NEW.src, NEW.dst) NOT IN (SELECT end2, end1 FROM FW0_policy_acl)) AND
              (NEW.src IN (SELECT * FROM FW0_policy_user))
       DO ALSO (
          INSERT INTO FW0_policy_acl VALUES (NEW.dst, NEW.src, 1);
       );

/* Remove whitelisted flow when removed form reachability matrix */
CREATE OR REPLACE RULE FW02 AS
       ON DELETE TO rm
       WHERE (SELECT count(*) FROM rm WHERE src = OLD.src AND dst = OLD.dst) = 1 AND
             (OLD.src IN (SELECT * FROM FW0_policy_user))
       DO ALSO
          DELETE FROM FW0_policy_acl WHERE end2 = OLD.src AND end1 = OLD.dst;

/* Violations - flows installed that are not in the host or node whitelist */
CREATE OR REPLACE VIEW FW0_violation AS (
       SELECT fid
       FROM rm
       WHERE FW0 = 1  AND (src, dst) NOT IN (SELECT end1, end2 FROM FW0_policy_acl)
);


DROP TABLE IF EXISTS FW1_policy_acl CASCADE;
CREATE UNLOGGED TABLE FW1_policy_acl (
       end1           integer,
       end2           integer,
       allow          integer,
       PRIMARY key (end1, end2)
);
CREATE INDEX ON FW1_policy_acl (end1,end2);

DROP TABLE IF EXISTS FW1_policy_user CASCADE;
CREATE UNLOGGED TABLE FW1_policy_user (
       uid            integer
);

CREATE OR REPLACE RULE FW11 AS
       ON INSERT TO rm
       WHERE ((NEW.src, NEW.dst) NOT IN (SELECT end2, end1 FROM FW1_policy_acl)) AND
              (NEW.src IN (SELECT * FROM FW1_policy_user))
       DO ALSO (
          INSERT INTO FW1_policy_acl VALUES (NEW.dst, NEW.src, 1);
       );

CREATE OR REPLACE RULE FW12 AS
       ON DELETE TO rm
       WHERE (SELECT count(*) FROM rm WHERE src = OLD.src AND dst = OLD.dst) = 1 AND
             (OLD.src IN (SELECT * FROM FW1_policy_user))
       DO ALSO
          DELETE FROM FW1_policy_acl WHERE end2 = OLD.src AND end1 = OLD.dst;

CREATE OR REPLACE VIEW FW1_violation AS (
       SELECT fid
       FROM rm
       WHERE FW1 = 1  AND (src, dst) NOT IN (SELECT end1, end2 FROM FW1_policy_acl)
);

DROP TABLE IF EXISTS FW2_policy_acl CASCADE;
CREATE UNLOGGED TABLE FW2_policy_acl (
       end1           integer,
       end2           integer,
       allow          integer,
       PRIMARY key (end1, end2)
);
CREATE INDEX ON FW2_policy_acl (end1,end2);

DROP TABLE IF EXISTS FW2_policy_user CASCADE;
CREATE UNLOGGED TABLE FW2_policy_user (
       uid            integer
);

CREATE OR REPLACE RULE FW21 AS
       ON INSERT TO rm
       WHERE ((NEW.src, NEW.dst) NOT IN (SELECT end2, end1 FROM FW2_policy_acl)) AND
              (NEW.src IN (SELECT * FROM FW2_policy_user))
       DO ALSO (
          INSERT INTO FW2_policy_acl VALUES (NEW.dst, NEW.src, 1);
       );

CREATE OR REPLACE RULE FW22 AS
       ON DELETE TO rm
       WHERE (SELECT count(*) FROM rm WHERE src = OLD.src AND dst = OLD.dst) = 1 AND
             (OLD.src IN (SELECT * FROM FW2_policy_user))
       DO ALSO
          DELETE FROM FW2_policy_acl WHERE end2 = OLD.src AND end1 = OLD.dst;


CREATE OR REPLACE VIEW FW2_violation AS (
       SELECT fid
       FROM rm
       WHERE FW2 = 1  AND (src, dst) NOT IN (SELECT end1, end2 FROM FW2_policy_acl)
);

CREATE OR REPLACE VIEW FW_violation AS (
	Select * from FW0_violation UNION
	Select * from FW1_violation UNION
	Select * from FW2_violation
);

/* Repair - remove proposed flows from the reachability matrix */
CREATE OR REPLACE RULE FW_repair AS
       ON DELETE TO FW_violation
       DO INSTEAD
          DELETE FROM rm WHERE fid = OLD.fid;




------------------------------------------------------------
-- SAMPLE CONFIGURATION (for toy_dtp.py topo)
------------------------------------------------------------
/* Same as CLI command (h4's hid=8, h3's hid=7):
 *    fw addflow h4 h3
 */
-- INSERT INTO FW_policy_acl (8,7,1);

/* Same as CLI command:
 *    fw addhost h2
 *    fw addhost h4
 */
-- INSERT INTO FW_policy_user VALUES (6), (8);
