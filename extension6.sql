DROP TABLE IF EXISTS rm CASCADE;
CREATE UNLOGGED TABLE rm (
fid         integer,
currentMB   text,
label       integer,
src         integer,
dst         integer,
vol         integer,
fw0         integer,
fw1         integer,
fw2         integer,
lb0         integer,
lb1         integer,
PRIMARY KEY (fid)
);
CREATE INDEX ON rm (fid,src,dst);

DROP TABLE IF EXISTS FLH CASCADE;
CREATE UNLOGGED TABLE FLH (
fid        integer,
currentMB  text,
newlabel   integer
);
CREATE INDEX ON FLH (fid,currentMB);

CREATE OR REPLACE RULE setnull AS
       ON insert TO FLH where new.newlabel=1
       DO also
       update rm set label=null, currentMB=new.currentMB where fid=new.fid;

CREATE OR REPLACE RULE deleteflow AS
       ON insert TO FLH where new.newlabel=-1
       DO instead(
            delete from rm where fid=new.fid;
            delete from FLH where fid=new.fid;
        );

CREATE OR REPLACE RULE update_rm AS
       ON insert TO FLH where new.newlabel=0
       DO also
       update rm set label=new.newlabel, currentMB=new.currentMB where fid=new.fid;

DROP TABLE IF EXISTS PGA_group CASCADE;
CREATE UNLOGGED TABLE PGA_group (
gid            integer,
sid_array      integer[],
PRIMARY key (gid)
);
CREATE INDEX ON PGA_group (gid);  

DROP TABLE IF EXISTS PGA_policy CASCADE;
CREATE UNLOGGED TABLE PGA_policy (
gid1         integer,
gid2         integer,
currentMB    text,
label        integer,
staticMB     text 
);
CREATE INDEX ON PGA_policy (gid1, gid2);

DROP TABLE IF EXISTS MB_policy CASCADE;
CREATE UNLOGGED TABLE MB_policy (
 gid1       integer,
 gid2       integer,  
 MB           text,
 dynamicMB    text 
);

DROP TABLE IF EXISTS Dynamic_policy CASCADE;
CREATE UNLOGGED TABLE Dynamic_policy (
 gid1       integer,
 gid2       integer, 
 currentMB  text,
 label      integer default 0,
 nextMB     text
);

CREATE OR REPLACE RULE GDP AS
       ON insert TO MB_policy
       DO also
       INSERT INTO Dynamic_policy (gid1,gid2,currentMB,nextMB) (select gid1, gid2, MB, dynamicMB from MB_policy where gid1=new.gid1 and gid2=new.gid2 and mb=new.mb and dynamicMB=new.dynamicMB);  
    
CREATE OR REPLACE RULE DDP AS
       ON delete TO MB_policy
       DO also
       delete from Dynamic_policy where gid1=old.gid1 and gid2=old.gid2 and currentMB=old.MB;

DROP VIEW IF EXISTS SPGA CASCADE;
CREATE OR REPLACE VIEW SPGA AS(
        WITH PGA_group_policy AS (
             SELECT p1.sid_array AS sa1,
                   p2.sid_array AS sa2,
                   currentMB,
                   label, 
                   staticMB AS nextMB
             FROM PGA_group p1, PGA_group p2, PGA_policy
             WHERE p1.gid = gid1 AND p2.gid = gid2),
            PGA_group_policy2 AS (
             SELECT unnest (sa1)"sid1", sa2, currentMB,label,nextMB
             FROM PGA_group_policy)
             SELECT sid1, unnest (sa2)"sid2",currentMB,label,nextMB
             FROM  PGA_group_policy2

);  

DROP VIEW IF EXISTS DPGA CASCADE;
CREATE OR REPLACE VIEW DPGA AS(
        WITH dynamic_group_policy AS (
             SELECT p1.sid_array AS sa1,
                    p2.sid_array AS sa2,
                    currentMB,
                    label, 
                    nextMB
             FROM PGA_group p1, PGA_group p2, dynamic_policy
             WHERE p1.gid = gid1 AND p2.gid = gid2),
            dynamic_group_policy2 AS (
             SELECT unnest (sa1)"sid1", sa2, currentMB,label,nextMB
             FROM dynamic_group_policy)
             SELECT sid1, unnest (sa2)"sid2",currentMB,label,nextMB
             FROM  dynamic_group_policy2 

);

DROP VIEW IF EXISTS PGA CASCADE;
CREATE OR REPLACE VIEW PGA AS(
    SELECT sid1,sid2,currentMB,label, nextmb FROM SPGA
    UNION
    SELECT sid1,sid2,currentMB,label,nextmb FROM DPGA
); 

CREATE OR REPLACE VIEW PGA_violation AS (
SELECT fid,nextMB
FROM rm, SPGA
WHERE src = sid1 AND dst = sid2 AND
       ((nextMB = 'fw0' AND fw0=0) OR (nextMB = 'fw0' AND fw0 IS NULL) OR
        (nextMB = 'fw1' AND fw1=0) OR (nextMB = 'fw1' AND fw1 IS NULL) OR
        (nextMB = 'fw2' AND fw2=0) OR (nextMB = 'fw2' AND fw2 IS NULL) OR
        (nextMB = 'lb0' AND lb0=0) OR (nextMB = 'lb0' AND lb0 IS NULL) OR
        (nextMB = 'lb1' AND lb1=0)  OR (nextMB = 'lb1' AND lb1 IS NULL))
UNION   
SELECT fid,nextMB
FROM rm, DPGA
WHERE src = sid1 AND dst = sid2 AND rm.label=DPGA.label AND rm.currentMB=DPGA.currentMB AND
       ((nextMB = 'fw0' AND fw0=0) OR (nextMB = 'fw0' AND fw0 IS NULL) OR
        (nextMB = 'fw1' AND fw1=0) OR (nextMB = 'fw1' AND fw1 IS NULL) OR
        (nextMB = 'fw2' AND fw2=0) OR (nextMB = 'fw2' AND fw2 IS NULL) OR
        (nextMB = 'lb0' AND lb0=0) OR (nextMB = 'lb0' AND lb0 IS NULL) OR
        (nextMB = 'lb1' AND lb1=0) OR (nextMB = 'lb1' AND lb1 IS NULL))
);

CREATE OR REPLACE RULE PGA_repair AS
ON DELETE TO PGA_violation
       DO INSTEAD
       (
         UPDATE rm SET fw0 = 1 WHERE fid = OLD.fid AND OLD.nextMB = 'fw0';
         UPDATE rm SET fw1 = 1 WHERE fid = OLD.fid AND OLD.nextMB = 'fw1';
         UPDATE rm SET fw2 = 1 WHERE fid = OLD.fid AND OLD.nextMB = 'fw2';
         UPDATE rm SET lb0 = 1 WHERE fid = OLD.fid AND OLD.nextMB = 'lb0';
         UPDATE rm SET lb1 = 1 WHERE fid = OLD.fid AND OLD.nextMB = 'lb1';
       );

INSERT INTO PGA_policy(gid1,gid2,staticMB) VALUES (1,2,'fw0'), (4,3,'lb0'),(0,1,'fw0');
insert into MB_policy values(1,2,'fw0','fw1'),(1,2,'fw1','fw2'),(4,3,'lb0','lb1');  
INSERT INTO PGA_group (gid, sid_array) VALUES (1, ARRAY[5]),(2, ARRAY[6]),(4,ARRAY[5,8]),(3,ARRAY[6,7]),(0,ARRAY[10]);
INSERT INTO rm (fid,src,dst) values (1,5,6),(2,5,7),(3,8,6),(4,8,7),(5,10,5);
insert into FLH(fid,currentMB,newlabel) values(1,'fw0',0);
select * from rm;
select * from PGA_violation;
delete from PGA_violation;
select * from rm;  
insert into FLH(fid,currentMB,newlabel) values(1,'fw1',-1);
select * from rm;
select * from PGA_violation;
delete from PGA_violation;
select * from rm;    
insert into FLH(fid,currentMB,newlabel) values(2,'lb0',0);
select * from rm;
select * from PGA_violation;
delete from PGA_violation;
select * from rm;    
insert into FLH(fid,currentMB,newlabel) values(2,'lb1',1);
select * from rm;
select * from PGA_violation;
delete from PGA_violation;
select * from rm;    
