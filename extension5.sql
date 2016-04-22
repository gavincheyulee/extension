/*label=1 means the flow is good and next dynamic fw isn't needed.
label=-1 means the flow is bad and shall be dropped.
label=0 means the flow is suspicious and the next dynamic fw is needed.
how to get pga view:
pga view is combined with pga_policy and dynamic_policy_for_flow line36-49
(this table is used to insert policies caused by the change of labels)line26-34
there are 3 possible violations:
1. label=0 in pga : delete the next dynamic fw=0 in rm
2. label=-1 in pag : delete this flow (there is sth wrong in this part from line 123 to 148)
3. label=1 in pga : set the all following dynamic fws=0 in rm
*/

DROP TABLE IF EXISTS PGA_policy CASCADE;
CREATE UNLOGGED TABLE PGA_policy (
gid1       integer,
gid2       integer,
label      integer,
MB         text 
);
CREATE INDEX ON PGA_policy (gid1, gid2);

DROP TABLE IF EXISTS PGA_group CASCADE;
CREATE UNLOGGED TABLE PGA_group (
gid            integer,
sid_array      integer[],
PRIMARY key (gid)
);
CREATE INDEX ON PGA_group (gid);

DROP TABLE IF EXISTS dynamic_policy_for_flow CASCADE;
CREATE UNLOGGED TABLE dynamic_policy_for_flow (
fid     integer,
src     integer,
dst     integer,
dynamicMB      text,
label   integer
);
CREATE INDEX ON dynamic_policy_for_flow (fid);

DROP VIEW IF EXISTS PGA CASCADE;
CREATE OR REPLACE VIEW PGA AS(
WITH PGA_group_policy AS (
SELECT p1.sid_array AS sa1,p2.sid_array AS sa2,MB,label
FROM PGA_group p1, PGA_group p2, PGA_policy
WHERE p1.gid = gid1 AND p2.gid = gid2),
PGA_group_policy2 AS (
SELECT unnest (sa1)"sid1", sa2, MB,label
FROM PGA_group_policy)
SELECT sid1, unnest (sa2)"sid2", MB,label
FROM  PGA_group_policy2
UNION
SELECT src AS sid1, dst AS sid2, dynamicMB AS MB,label from dynamic_policy_for_flow
);

DROP TABLE IF EXISTS rm CASCADE;
CREATE UNLOGGED TABLE rm (
fid      integer,
src      integer,
dst      integer,
vol      integer,
FW0      integer,
FW1      integer,
FW2      integer,
LB0      integer,
PRIMARY KEY (fid)
);
CREATE INDEX ON rm (fid,src,dst);

CREATE UNLOGGED TABLE flow_label(
fid     integer,
src     integer,
dst     integer,
label   integer,
currentMB text,
PRIMARY KEY(fid)
);
CREATE INDEX ON flow_label (fid);


CREATE FUNCTION labelaction()
RETURNS trigger AS $$
DECLARE
BEGIN
IF NEW.currentMB='fw0' THEN
     INSERT INTO dynamic_policy_for_flow VALUES (NEW.fid,NEW.src,NEW.dst,'FW1',NEW.label);
ELSIF NEW.currentMB='fw1' THEN
     INSERT INTO dynamic_policy_for_flow VALUES (NEW.fid,NEW.src,NEW.dst,'FW2',NEW.label);
END IF;       
RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_labelaction
AFTER INSERT
ON flow_label
FOR EACH ROW
EXECUTE PROCEDURE labelaction();  



CREATE OR REPLACE VIEW PGA_violation1 AS (
SELECT fid,MB
FROM rm, PGA
WHERE src = sid1 AND dst = sid2 AND
       ((MB = 'FW0' AND FW0=0 and label is null) OR (MB = 'FW0' AND FW0 IS NULL and label is null) OR
        (MB = 'FW1' AND FW1=0 AND label=0) OR (MB = 'FW1' AND FW1 IS NULL AND label=0) OR
        (MB = 'FW2' AND FW2=0 AND label=0) OR (MB = 'FW2' AND FW2 IS NULL AND label=0) OR
        (MB = 'LB0' AND LB0=0 and label is null) OR (MB = 'LB0' AND LB0 IS NULL and label is null))
);

CREATE OR REPLACE RULE PGA_repair1 AS
ON DELETE TO PGA_violation1
       DO INSTEAD
       (
         UPDATE rm SET FW0 = 1 WHERE fid = OLD.fid AND OLD.MB = 'FW0';
         UPDATE rm SET FW1 = 1 WHERE fid = OLD.fid AND OLD.MB = 'FW1';
         UPDATE rm SET FW2 = 1 WHERE fid = OLD.fid AND OLD.MB = 'FW2';
         UPDATE rm SET LB0 = 1 WHERE fid = OLD.fid AND OLD.MB = 'LB0';
       );



CREATE OR REPLACE VIEW PGA_violation2 AS (
SELECT fid,MB
FROM rm, PGA
WHERE src = sid1 AND dst = sid2 AND label=-1
);

CREATE OR REPLACE RULE PGA_repair2 AS
ON DELETE TO PGA_violation2
       DO INSTEAD DELETE FROM rm where fid=OLD.fid;


CREATE OR REPLACE RULE deleteflowlabel AS
ON DELETE TO rm
DO ALSO
DELETE FROM flow_label  WHERE fid=OLD.fid;

CREATE OR REPLACE RULE deleteDynamic AS
ON DELETE TO rm
DO ALSO
DELETE FROM dynamic_policy_for_flow  WHERE fid=OLD.fid;

CREATE OR REPLACE VIEW PGA_violation3 AS (
SELECT fid,MB
FROM rm, PGA
WHERE src = sid1 AND dst = sid2 AND label=1
);

CREATE OR REPLACE RULE PGA_repair3 AS
ON DELETE TO PGA_violation3
       DO INSTEAD
       (
        UPDATE rm SET FW1=0, FW2=0 where fid=OLD.fid AND OLD.MB='FW1';
        UPDATE rm SET FW2=0 where fid=OLD.fid AND OLD.MB='FW2';
       );

--------
INSERT INTO PGA_policy (gid1, gid2, MB) VALUES (1,2,'FW0'), (4,3,'LB0');
INSERT INTO PGA_group (gid, sid_array) VALUES (1, ARRAY[5]),(2, ARRAY[6]),(4,ARRAY[5,8]),(3,ARRAY[6,7]);
INSERT INTO rm (fid,src,dst,fw0,lb0) values (1,5,6,1,1),(2,5,7,0,1),(3,8,6,0,1),(4,8,7,0,1);
INSERT INTO dynamic_policy_for_flow(fid,src,dst,dynamicMB,label) values (1,5,6,'FW1',0);
INSERT INTO flow_label values (1,5,6,0,'fw0');
delete from  PGA_violation1;
