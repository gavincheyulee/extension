/*This is not a complete version. I just want you to check if this schema is what you are expecting. In this version, you can try dynamic scenes with FW. There are three fw in total: fw0, fw1,fw2
label=null means the flow must go through fw0 and my need dynamic FW.
label=1 means dynamic FW1 is needed
label=2 means dynamic FW2 is needed
*/
DROP TABLE IF EXISTS PGA_policy CASCADE;
CREATE UNLOGGED TABLE PGA_policy (
gid1           integer,
gid2           integer,
plabel          integer,
MB             text
);
CREATE INDEX ON PGA_policy (gid1, gid2);


DROP TABLE IF EXISTS PGA_group CASCADE;
CREATE UNLOGGED TABLE PGA_group (
       gid        integer,
       sid_array      integer[],
       PRIMARY key (gid)
);
CREATE INDEX ON PGA_group (gid);

DROP VIEW IF EXISTS PGA CASCADE;
CREATE OR REPLACE VIEW PGA AS(
       WITH PGA_group_policy AS (
            SELECT p1.sid_array AS sa1,
                   p2.sid_array AS sa2,plabel, MB
            FROM PGA_group p1, PGA_group p2, PGA_policy
            WHERE p1.gid = gid1 AND p2.gid = gid2),
       PGA_group_policy2 AS (
            SELECT unnest (sa1)"sid1", sa2, plabel,MB
        FROM PGA_group_policy)
       SELECT sid1, unnest (sa2)"sid2",plabel, MB
       FROM  PGA_group_policy2
);

CREATE OR REPLACE VIEW PGA_violation AS (
SELECT fid, MB
FROM rm, PGA
WHERE src = sid1 AND dst = sid2 AND label=plabel AND
       ((MB = 'FW0' AND FW0=0) OR (MB = 'FW0' AND FW0 IS NULL) OR
        (MB = 'FW1' AND FW1=0) OR (MB = 'FW1' AND FW1 IS NULL) OR
        (MB = 'FW2' AND FW2=0) OR (MB = 'FW2' AND FW2 IS NULL) OR
        (MB='LB' AND LB=0))
);

CREATE OR REPLACE RULE PGA_repair AS
ON DELETE TO PGA_violation
       DO INSTEAD
       (
         UPDATE rm SET FW0 = 1 WHERE fid = OLD.fid AND OLD.MB = 'FW0';
         UPDATE rm SET FW1 = 1 WHERE fid = OLD.fid AND OLD.MB = 'FW1';
         UPDATE rm SET FW0 = 1 WHERE fid = OLD.fid AND OLD.MB = 'FW2';
         UPDATE rm SET LB = 1 WHERE fid = OLD.fid AND OLD.MB = 'LB';
       );


DROP TABLE IF EXISTS rm CASCADE;
CREATE UNLOGGED TABLE rm (
fid      integer,
label    integer,
src      integer,
dst      integer,
vol      integer,
FW0      integer,
FW1      integer,
FW2      integer,
LB       integer,
PRIMARY KEY (fid)
);
CREATE INDEX ON rm (fid,src,dst);

CREATE UNLOGGED TABLE flow_label(
fid     integer,
label   integer,
PRIMARY KEY(fid)
);
CREATE INDEX ON flow_label (fid);

CREATE OR REPLACE RULE flow1 AS
ON INSERT TO rm
DO ALSO (
INSERT INTO flow_label VALUES (NEW.fid, NEW.label)
);

CREATE OR REPLACE RULE flow2 AS
ON DELETE TO rm
DO ALSO
DELETE FROM flow_label WHERE fid=OLD.fid;

CREATE FUNCTION rm_modify() 
RETURNS trigger AS $$
DECLARE
BEGIN
IF OLD.label IS NULL THEN
    IF NEW.label=0 THEN
       UPDATE rm 
       SET label=NEW.label,FW1=0,FW2=0
       WHERE fid=NEW.fid;
    ELSIF NEW.label=1 THEN
       UPDATE rm 
       SET label=NEW.label,FW1=1
       WHERE fid=NEW.fid;
    END IF;           
ELSIF OLD.label=1 THEN
    IF NEW.label=0 THEN
       UPDATE rm 
       SET label=NEW.label,FW2=0
       WHERE fid=OLD.fid;
    ELSIF NEW.label=2 THEN
       UPDATE rm 
       SET label=NEW.label,FW2=1
       WHERE fid=OLD.fid;
    END IF;
END IF;  
RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_rm_modify
AFTER UPDATE 
ON flow_label
FOR EACH ROW
EXECUTE PROCEDURE rm_modify();

CREATE FUNCTION policy_modify() 
RETURNS trigger AS $$
DECLARE
BEGIN
IF NEW.plabel IS NULL THEN
       INSERT INTO pga_policy 
       VALUES(NEW.gid1,NEW.gid2,1,'FW0'),(NEW.gid1,NEW.gid2,1,'FW1'),
       (NEW.gid1,NEW.gid2,2,'FW0'),(NEW.gid1,NEW.gid2,2,'FW1'),
       (NEW.gid1,NEW.gid2,2,'FW2');
END IF;  
RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_policy_modify
AFTER INSERT
ON PGA_policy
FOR EACH ROW
EXECUTE PROCEDURE policy_modify();

INSERT INTO PGA_policy (gid1,gid2,mb) values(5,6,'FW');
INSERT INTO PGA_group (gid, sid_array) VALUES (5,ARRAY[2]), (6,ARRAY[3]);
INSERT INTO rm (fid,src,dst,fw0,lb) values (1,2,3,0,0);
INSERT INTO rm (fid,src,dst,fw0,lb) values (2,2,3,1,0);
INSERT INTO rm (fid,label,src,dst,fw0,lb) values (3,1,2,3,1,0);
select * from PGA_policy;
select * from PGA_violation;
delete from PGA_violation where fid=3;
select * from rm;
update flow_label
set label=0
where fid=1;

