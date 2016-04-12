/*
There are three fw in total: fw0, fw1,fw2 and three lb in total:lb0,lb1,lb3
label=null means the flow must go through fw0/lb0 and may need dynamic FW/LB.
label=1 means the flow is good and next dynamic MB isn't needed.
label=-1 means the flow is bad and shall be dropped.
label=0 means the flow is suspicious and the next dynamic MB is needed.
*/
DROP TABLE IF EXISTS PGA_policy CASCADE;
CREATE UNLOGGED TABLE PGA_policy (
gid1           integer,
gid2           integer,
plabel         integer,
MB             text
);
CREATE INDEX ON PGA_policy (gid1, gid2);

DROP TABLE IF EXISTS PGA_group CASCADE;
CREATE UNLOGGED TABLE PGA_group (
       gid            integer,
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
LB0      integer,
LB1      integer,
LB2      integer,
PRIMARY KEY (fid)
);
CREATE INDEX ON rm (fid,src,dst);

CREATE UNLOGGED TABLE flow_label(
fid     integer,
label   integer,
currentMB text,
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

CREATE OR REPLACE VIEW PGA_violation AS (
SELECT fid, MB
FROM rm, PGA
WHERE src = sid1 AND dst = sid2 AND ((label IS NULL AND plabel IS NULL) OR label=plabel) AND
       ((MB = 'FW0' AND FW0=0) OR (MB = 'FW0' AND FW0 IS NULL) OR
        (MB = 'LB0' AND LB0=0) OR (MB = 'LB0' AND LB0 IS NULL))
);

CREATE OR REPLACE RULE PGA_repair AS
ON DELETE TO PGA_violation
       DO INSTEAD
       (
         UPDATE rm SET FW0 = 1 WHERE fid = OLD.fid AND OLD.MB = 'FW0';
         UPDATE rm SET LB0 = 1 WHERE fid = OLD.fid AND OLD.MB = 'LB0';
       );

CREATE FUNCTION rm_modify() 
RETURNS trigger AS $$
BEGIN
IF NEW.currentMB='FW0' THEN
    IF NEW.label=1 THEN
       UPDATE rm 
       SET label=NEW.label,FW1=0,FW2=0
       WHERE fid=NEW.fid;
    ELSIF NEW.label=-1 THEN
       DELETE FROM rm 
       WHERE fid=NEW.fid;    
    ELSIF NEW.label=0 THEN
       UPDATE rm 
       SET label=NEW.label,FW1=1
       WHERE fid=NEW.fid;
    END IF;  
ELSIF NEW.currentMB='FW1' THEN
    IF NEW.label=1 THEN
       UPDATE rm 
       SET label=NEW.label,FW2=0
       WHERE fid=NEW.fid;
    ELSIF NEW.label=-1 THEN
       DELETE FROM rm 
       WHERE fid=NEW.fid;    
    ELSIF NEW.label=0 THEN
       UPDATE rm 
       SET label=NEW.label,FW2=1
       WHERE fid=NEW.fid;
    END IF;              
ELSIF NEW.currentMB='FW2' THEN
    IF NEW.label=1 THEN
       UPDATE rm 
       SET label=NEW.label
       WHERE fid=NEW.fid;
    ELSIF NEW.label=-1 THEN
       DELETE FROM rm 
       WHERE fid=NEW.fid;    
    ELSIF NEW.label=0 THEN
       DELETE FROM rm 
       WHERE fid=NEW.fid; 
    END IF;
ELSIF NEW.currentMB='LB0' THEN
    IF NEW.label=1 THEN
       UPDATE rm 
       SET label=NEW.label,LB1=0,LB2=0
       WHERE fid=NEW.fid;
    ELSIF NEW.label=-1 THEN
       DELETE FROM rm 
       WHERE fid=NEW.fid;    
    ELSIF NEW.label=0 THEN
       UPDATE rm 
       SET label=NEW.label,LB1=1
       WHERE fid=NEW.fid;
    END IF;  
ELSIF NEW.currentMB='LB1' THEN
    IF NEW.label=1 THEN
       UPDATE rm 
       SET label=NEW.label,LB2=0
       WHERE fid=NEW.fid;
    ELSIF NEW.label=-1 THEN
       DELETE FROM rm 
       WHERE fid=NEW.fid;    
    ELSIF NEW.label=0 THEN
       UPDATE rm 
       SET label=NEW.label,LB2=1
       WHERE fid=NEW.fid;
    END IF;              
ELSIF NEW.currentMB='LB2' THEN
    IF NEW.label=1 THEN
       UPDATE rm 
       SET label=NEW.label
       WHERE fid=NEW.fid;
    ELSIF NEW.label=-1 THEN
       DELETE FROM rm 
       WHERE fid=NEW.fid;    
    ELSIF NEW.label=0 THEN
       DELETE FROM rm 
       WHERE fid=NEW.fid; 
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
    IF NEW.MB='FW0' THEN
       INSERT INTO pga_policy 
       VALUES(NEW.gid1,NEW.gid2,1,'FW0'),(NEW.gid1,NEW.gid2,0,'FW0');
    ELSIF NEW.MB='LB0' THEN
       INSERT INTO pga_policy 
       VALUES(NEW.gid1,NEW.gid2,1,'LB0'),(NEW.gid1,NEW.gid2,0,'LB0'); 
    END IF;                    
END IF;    
RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_policy_modify
AFTER INSERT
ON PGA_policy
FOR EACH ROW
EXECUTE PROCEDURE policy_modify();

INSERT INTO PGA_policy (gid1,gid2,mb) values(1,2,'FW0');
INSERT INTO PGA_policy (gid1,gid2,mb) values(1,2,'LB0');
INSERT INTO PGA_policy (gid1,gid2,mb) values(3,4,'LB0');
INSERT INTO PGA_policy (gid1,gid2,mb) values(5,6,'FW0');
INSERT INTO PGA_policy (gid1,gid2,mb) values(1,4,'FW0');
INSERT INTO PGA_group (gid, sid_array) VALUES (1,ARRAY[2]), (2,ARRAY[1]),(3,ARRAY[5]),(4,ARRAY[7]),(5,ARRAY[5]),(6,ARRAY[7]);
INSERT INTO rm (fid,src,dst,fw0,lb0) values (1,2,1,0,0);
INSERT INTO rm (fid,src,dst,fw0,lb0) values (2,5,7,1,0);
INSERT INTO rm (fid,src,dst,fw0,lb0) values (3,2,7,0,0);
select * from rm;
select * from PGA_violation;
delete from PGA_violation;
select * from rm;


update flow_label
set label=0,currentMB='LB0'
where fid=1;
select * from rm;
update flow_label
set label=1,currentMB='LB1'
where fid=1;
select * from rm;
update flow_label
set label=0,currentMB='FW0'
where fid=1;
select * from rm;
update flow_label
set label=0,currentMB='FW1'
where fid=1;
select * from rm;
update flow_label
set label=-1,currentMB='FW2'
where fid=1;
select * from rm;



update flow_label
set label=0,currentMB='LB0'
where fid=3;
select * from rm;
update flow_label
set label=-1,currentMB='LB1'
where fid=3;
select * from rm;
