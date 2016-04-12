/*
There are three fw in total: fw0, fw1,fw2 and three lb in total:lb0,lb1,lb3
all possible cases:
(1)only fw or lb on the way
(2)both fw and lb on the way 
label=null means the flow must go through fw0/lb0/(fw0&lb0) and may need dynamic FW/LB.
label=1 means dynamic FW1 is needed
label=2 means dynamic FW2 is needed
label=3 means dynamic LB1 is needed
lbael=4 means dynamic LB2 is needed
label=-1 means next dynamic FW is not needed
label=-2 means next dynamic LB is not needed
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

CREATE OR REPLACE VIEW PGA_violation AS (
SELECT fid, MB
FROM rm, PGA
WHERE src = sid1 AND dst = sid2 AND ((label IS NULL AND plabel IS NULL) OR label=plabel) AND
       ((MB = 'FW0' AND FW0=0) OR (MB = 'FW0' AND FW0 IS NULL) OR
        (MB = 'FW1' AND FW1=0) OR (MB = 'FW1' AND FW1 IS NULL) OR
        (MB = 'FW2' AND FW2=0) OR (MB = 'FW2' AND FW2 IS NULL) OR
        (MB = 'LB0' AND LB0=0) OR (MB = 'LB0' AND LB0 IS NULL) OR
        (MB = 'LB1' AND LB1=0) OR (MB = 'LB1' AND LB1 IS NULL) OR
        (MB = 'LB2' AND LB2=0) OR (MB = 'LB2' AND LB2 IS NULL))
);

CREATE OR REPLACE RULE PGA_repair AS
ON DELETE TO PGA_violation
       DO INSTEAD
       (
         UPDATE rm SET FW0 = 1 WHERE fid = OLD.fid AND OLD.MB = 'FW0';
         UPDATE rm SET FW1 = 1 WHERE fid = OLD.fid AND OLD.MB = 'FW1';
         UPDATE rm SET FW2 = 1 WHERE fid = OLD.fid AND OLD.MB = 'FW2';
         UPDATE rm SET LB0 = 1 WHERE fid = OLD.fid AND OLD.MB = 'LB0';
         UPDATE rm SET LB1 = 1 WHERE fid = OLD.fid AND OLD.MB = 'LB1';
         UPDATE rm SET LB2 = 1 WHERE fid = OLD.fid AND OLD.MB = 'LB2';
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
    IF NEW.label=-1 THEN
       UPDATE rm 
       SET label=NEW.label,FW1=0,FW2=0
       WHERE fid=NEW.fid;
    ELSIF NEW.label=-2 THEN
       UPDATE rm 
       SET label=NEW.label,LB1=0,LB2=0
       WHERE fid=NEW.fid;    
    ELSIF NEW.label=1 THEN
       UPDATE rm 
       SET label=NEW.label,FW1=1
       WHERE fid=NEW.fid;
    ELSIF NEW.label=3 THEN
       UPDATE rm 
       SET label=NEW.label,LB1=1
       WHERE fid=NEW.fid;
    END IF;  
ELSIF OLD.label=1 THEN
    IF NEW.label=-1 THEN
       UPDATE rm 
       SET label=NEW.label,FW2=0
       WHERE fid=NEW.fid;
    ELSIF NEW.label=2 THEN
       UPDATE rm 
       SET label=NEW.label,FW2=1
       WHERE fid=NEW.fid;
    END IF;  
ELSIF OLD.label=2 THEN
    IF NEW.label=-1 THEN
       UPDATE rm 
       SET label=NEW.label
       WHERE fid=NEW.fid;
    END IF;            
ELSIF OLD.label=3 THEN
    IF NEW.label=-2 THEN
       UPDATE rm 
       SET label=NEW.label,LB2=0
       WHERE fid=NEW.fid;
    ELSIF NEW.label=4 THEN
       UPDATE rm 
       SET label=NEW.label,LB2=1
       WHERE fid=NEW.fid;
    END IF; 
ELSIF OLD.label=4 THEN
    IF NEW.label=-2 THEN
       UPDATE rm 
       SET label=NEW.label
       WHERE fid=NEW.fid;
    END IF;     
ELSIF OLD.label=-1 THEN
    IF NEW.label=3 THEN
       UPDATE rm 
       SET label=NEW.label,LB1=1
       WHERE fid=NEW.fid;
    ELSIF NEW.label=-2 THEN   
       UPDATE rm 
       SET label=NEW.label,LB1=0,LB2=0
       WHERE fid=NEW.fid;   
    END IF;      
ELSIF OLD.label=-2 THEN
    IF NEW.label=1 THEN
       UPDATE rm 
       SET label=NEW.label,FW1=1
       WHERE fid=NEW.fid;
    ELSIF NEW.label=-1 THEN   
       UPDATE rm 
       SET label=NEW.label,FW1=0,FW2=0
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
number integer;
BEGIN
number=(SELECT count(*) FROM pga_policy WHERE gid1 = NEW.gid1 AND gid2 = NEW.gid2);
IF NEW.plabel IS NULL THEN
  IF number=1 THEN
    IF NEW.MB='FW0' THEN
       INSERT INTO pga_policy 
       VALUES(NEW.gid1,NEW.gid2,1,'FW0'),(NEW.gid1,NEW.gid2,1,'FW1'),
       (NEW.gid1,NEW.gid2,2,'FW0'),(NEW.gid1,NEW.gid2,2,'FW1'),
       (NEW.gid1,NEW.gid2,2,'FW2');
    ELSIF NEW.MB='LB0' THEN
       INSERT INTO pga_policy 
       VALUES(NEW.gid1,NEW.gid2,3,'LB0'),(NEW.gid1,NEW.gid2,3,'LB1'),
       (NEW.gid1,NEW.gid2,4,'LB0'),(NEW.gid1,NEW.gid2,4,'LB1'),
       (NEW.gid1,NEW.gid2,4,'LB2');  
    END IF;            
  ELSIF number>1 THEN
    DELETE FROM pga_policy WHERE gid1 = NEW.gid1 AND gid2 = NEW.gid2 AND plabel IS NOT NULL;
    INSERT INTO pga_policy 
       VALUES(NEW.gid1,NEW.gid2,1,'FW0'),(NEW.gid1,NEW.gid2,1,'FW1'),(NEW.gid1,NEW.gid2,1,'LB0'),
             (NEW.gid1,NEW.gid2,2,'FW0'),(NEW.gid1,NEW.gid2,2,'FW1'),(NEW.gid1,NEW.gid2,2,'FW2'),(NEW.gid1,NEW.gid2,2,'LB0'),
             (NEW.gid1,NEW.gid2,3,'LB0'),(NEW.gid1,NEW.gid2,3,'LB1'),(NEW.gid1,NEW.gid2,3,'FW0'),
             (NEW.gid1,NEW.gid2,4,'LB0'),(NEW.gid1,NEW.gid2,4,'LB1'),(NEW.gid1,NEW.gid2,4,'LB2'),(NEW.gid1,NEW.gid2,4,'FW0'), 
             (NEW.gid1,NEW.gid2,-1,'FW0'),(NEW.gid1,NEW.gid2,-1,'LB0'),
             (NEW.gid1,NEW.gid2,-2,'FW0'),(NEW.gid1,NEW.gid2,-2,'LB0');
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

INSERT INTO PGA_policy (gid1,gid2,mb) values(5,6,'FW0');
INSERT INTO PGA_policy (gid1,gid2,mb) values(5,6,'LB0');
INSERT INTO PGA_group (gid, sid_array) VALUES (5,ARRAY[2,4]), (6,ARRAY[1,3]);
INSERT INTO rm (fid,src,dst,fw0,lb0) values (1,2,3,0,0);
INSERT INTO rm (fid,src,dst,fw0,lb0) values (2,4,1,1,0);
select * from rm;
select * from PGA_violation;
delete from PGA_violation;
select * from rm;
update flow_label
set label=-1
where fid=1;
select * from rm;
update flow_label
set label=-2
where fid=1;
select * from rm;
update flow_label
set label=3
where fid=2;
select * from rm;
update flow_label
set label=4
where fid=2;
select * from rm;
update flow_label
set label=-2
where fid=2;
select * from rm;
update flow_label
set label=1
where fid=2;
select * from rm;
update flow_label
set label=-1
where fid=2;
select * from rm;


