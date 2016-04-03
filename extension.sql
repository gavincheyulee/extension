DROP TABLE IF EXISTS PGA_policy CASCADE;
CREATE UNLOGGED TABLE PGA_policy (
gid1       integer,
gid2       integer,
MB         text,
Label      integer,
extraMB    text,
PRIMARY key (gid1, gid2,Label)
);
CREATE INDEX ON PGA_policy (gid1, gid2,Label);


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
SELECT p1.sid_array AS sa1,p2.sid_array AS sa2,MB,Label,extraMB 
FROM PGA_group p1, PGA_group p2, PGA_policy
WHERE p1.gid = gid1 AND p2.gid = gid2),
PGA_group_policy2 AS (
SELECT unnest (sa1)"sid1", sa2, MB,Label,extraMB 
FROM PGA_group_policy)
SELECT sid1, unnest (sa2)"sid2", MB,Label,extraMB 
FROM  PGA_group_policy2
);


DROP TABLE IF EXISTS rm CASCADE;
CREATE UNLOGGED TABLE rm (
fid      integer,
src      integer,
dst      integer,
vol      integer,
FW       integer,
LB       integer,
PRIMARY KEY (fid)
);
CREATE INDEX ON rm (fid,src,dst);


CREATE OR REPLACE VIEW MBPGA_violation AS (
SELECT fid, MB
FROM rm, PGA
WHERE src = sid1 AND dst = sid2 AND
((MB = 'FW' AND FW=0) OR (MB='LB' AND LB=0))
);


CREATE OR REPLACE VIEW EMBPGA_violation AS (
SELECT fid, extraMB
FROM rm, PGA
WHERE src = sid1 AND dst = sid2 AND
((extraMB = 'FW' AND FW=0)OR(extraMB='LB' AND LB=0))
);


CREATE OR REPLACE VIEW PGA_violation AS (
SELECT fid, MB,extraMB
FROM rm, PGA
WHERE src = sid1 AND dst = sid2 AND
((MB = 'FW' AND FW=0) OR (MB='LB' AND LB=0)OR(extraMB = 'FW' AND FW=0)OR(extraMB='LB' AND LB=0))
);


CREATE OR REPLACE RULE MBPGA_repair AS
ON DELETE TO MBPGA_violation
DO INSTEAD
(
UPDATE rm SET FW = 1 WHERE fid = OLD.fid AND OLD.MB = 'FW';
UPDATE rm SET LB = 1 WHERE fid = OLD.fid AND OLD.MB = 'LB';
);


CREATE OR REPLACE RULE EMBPGA_repair AS
ON DELETE TO EMBPGA_violation
DO INSTEAD
(
UPDATE rm SET FW = 1 WHERE fid = OLD.fid AND OLD.extraMB = 'FW';
UPDATE rm SET LB = 1 WHERE fid = OLD.fid AND OLD.extraMB = 'LB';
);





/*
INSERT INTO PGA_policy (gid1, gid2, MB,Label,extraMB) 
VALUES (1,2,'FW',0,'FW'),(1,2,'FW',1,'NULL'),(4,3,'LB',0,'FW'),(4,3,'LB',1,'NULL');

INSERT INTO PGA_group (gid, sid_array) VALUES (1,ARRAY[5]), (2,ARRAY[6]),(4,ARRAY[5,8]),(3,ARRAY[6,7]);

INSERT INTO rm (fid, src, dst,vol,FW,LB) VALUES (1,5,6,8,1,1), (2,5,7,8,0,1),(3,8,6,8,1,1),(4,5,7,8,1,0);
*/