/*flow label history*/
DROP TABLE IF EXISTS FLH CASCADE;
CREATE UNLOGGED TABLE FLH (
fid        integer,
currentMB  text,
newlabel   integer
);
CREATE INDEX ON FLH (fid,currentMB);

/*an mb settung label=1 means this dynamic chain has finished*/
/*flow will go to another kind of mb or to the dst*/
/*setting the label null in rm helps next mb work well*/
CREATE OR REPLACE RULE setnull AS
       ON insert TO FLH where new.newlabel=1
       DO also
       update rm set label=null, currentMB=new.currentMB where fid=new.fid;

/*an mb setting a label=-1 means this flow is bad,so delete it*/
CREATE OR REPLACE RULE deleteflow AS
       ON insert TO FLH where new.newlabel=-1
       DO instead(
            delete from rm where fid=new.fid;
            delete from FLH where fid=new.fid;
        );

/*an mb sets its label=0(suspicious),set it in rm too*/
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
/*label and currentmb in pga_policy are useless, they are null*/
/*just to get a unified format for view DPGA and SPGA*/
DROP TABLE IF EXISTS PGA_policy CASCADE;
CREATE UNLOGGED TABLE PGA_policy (
gid1         integer,
gid2         integer,
currentMB    text,
label        integer,
staticMB     text 
);
CREATE INDEX ON PGA_policy (gid1, gid2);

/*for a specific flow, defines its static mbs' dynamic mbs*/
/*may not need dynamic mb for a certain mb*/
/*just depend on policy writer*/
DROP TABLE IF EXISTS MB_policy CASCADE;
CREATE UNLOGGED TABLE MB_policy (
 gid1       integer,
 gid2       integer,  
 MB           text,
 dynamicMB    text 
);

/*this is the counterpart of pga_policy*/
/*only when the label=0, need to use dynamic mb, so label has its default value 0*/
DROP TABLE IF EXISTS Dynamic_policy CASCADE;
CREATE UNLOGGED TABLE Dynamic_policy (
 gid1       integer,
 gid2       integer, 
 currentMB  text,
 label      integer default 0,
 nextMB     text
);

/*generate dynamic policy*/
/*statically generate all possible policies so that each flow can find useful policy according to its label and current mb*/
CREATE OR REPLACE RULE GDP AS
       ON insert TO MB_policy
       DO also
       INSERT INTO Dynamic_policy (gid1,gid2,currentMB,nextMB) (select gid1, gid2, MB, dynamicMB from MB_policy where gid1=new.gid1 and gid2=new.gid2 and mb=new.mb and dynamicMB=new.dynamicMB);  
   
/*delete dynamic policy according to mb_policy*/ 
CREATE OR REPLACE RULE DDP AS
       ON delete TO MB_policy
       DO also
       delete from Dynamic_policy where gid1=old.gid1 and gid2=old.gid2 and currentMB=old.MB;

/*static polciy for end-level*/
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
/*dynamic policy for end-level*/
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

/*policy for end-level*/
DROP VIEW IF EXISTS PGA CASCADE;
CREATE OR REPLACE VIEW PGA AS(
    SELECT sid1,sid2,currentMB,label, nextmb FROM SPGA
    UNION
    SELECT sid1,sid2,currentMB,label,nextmb FROM DPGA
); 

/*create view PGA_violation*/
CREATE OR REPLACE FUNCTION createvio_fun() RETURNS text AS
$$
cname=plpy.execute("select column_name from information_schema.columns where table_name='rm';")
mblist = []
sql1=""
sql2=""
for t in cname:
    if (t["column_name"] !="fid" and t["column_name"] !="currentmb" and t["column_name"] !="label" and 
       t["column_name"] !="src" and t["column_name"] !="dst" and t["column_name"] !="vol"): 
       mblist.append(t["column_name"])
for m in mblist:  
      sql1=sql1+"(nextMB = " + "'" +str(m) + "'" + " AND "+ m + "=0) OR (nextMB = "+ "'" +str(m) + "'" + " AND " + m + " IS NULL) OR "
statement1=sql1[:-4]
violation="""CREATE OR REPLACE VIEW DPGA_violation AS (
SELECT fid,nextMB
FROM rm, SPGA
WHERE src = sid1 AND dst = sid2 AND
("""+statement1+""")
UNION   
SELECT fid,nextMB
FROM rm, DPGA
WHERE src = sid1 AND dst = sid2 AND rm.label=DPGA.label AND rm.currentMB=DPGA.currentMB AND
("""+statement1+""")
);"""
plpy.execute(violation)
return "success";
$$
LANGUAGE 'plpythonu' VOLATILE SECURITY DEFINER;
select createvio_fun();

/*create view PGA_repair*/
CREATE OR REPLACE FUNCTION createrep_fun() RETURNS text AS
$$
cname=plpy.execute("select column_name from information_schema.columns where table_name='rm';")
mblist = []
sql2=""
for t in cname:
    if (t["column_name"] !="fid" and t["column_name"] !="currentmb" and t["column_name"] !="label" and 
       t["column_name"] !="src" and t["column_name"] !="dst" and t["column_name"] !="vol"): 
       mblist.append(t["column_name"])
for n in mblist:        
      sql2=sql2+" UPDATE rm SET " + str(n) +" = 1 WHERE fid = OLD.fid AND OLD.nextMB = '" + str(n) + "'; "
statement2=sql2[:-1]
repair="""CREATE OR REPLACE RULE DPGA_repair AS
ON DELETE TO DPGA_violation
       DO INSTEAD
       ("""+statement2+""");"""
plpy.execute(repair)
return "success";
$$
LANGUAGE 'plpythonu' VOLATILE SECURITY DEFINER;
select createrep_fun();





