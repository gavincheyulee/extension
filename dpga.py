import cmd
from ravel.app import AppConsole

class DpgaConsole(AppConsole):
    def _getHostId(self, hname):
        hostnames = self.env.provider.cache_name
        if hname not in hostnames:
            print "Unknown host", hname
            return None

        return hostnames[hname]

    def do_addpgapolicy(self, line):
        """Add static policies for groups
           Usage: addpgapolicy [groupid1] [groupid2] [mbname]"""      
	args = line.split()
        if len(args) !=3:
            print "Invalid syntax"
            return
	str1="INSERT INTO PGA_policy(gid1,gid2,staticMB) values({0},{1},'{2}');".format(args[0],args[1],args[2])
					
        try:
            self.db.cursor.execute(str1)
        except Exception, e:
            print "Failure: policy not added --", e
            return

        print "Success: (gid{0} gid{1} {2})added to PGA_policy".format(args[0],args[1],args[2])

    def do_addmember(self, line):
        """Add hosts to a group
           Usage: addmember [groupid] [hostname1,hostname2,......]"""
	for i in (','):
		line=line.replace(i,' ')        
	args = line.split()
        if len(args) <2:
            print "Invalid syntax"
            return
	gid=int(args[0])
	sidarray=[]
	for i in range(1,len(args)):
		hostid = self._getHostId(args[i])
        	if hostid is None:
            		return
		else:
			sidarray.append(hostid)

	str1="ARRAY["
	for i in range(len(sidarray)):
		str1=str1+str(sidarray[i])+','
	str1=str1[:-1]+']'
	str2="INSERT INTO PGA_group VALUES ({0},".format(gid)+str1+");"
        try:
            self.db.cursor.execute(str2)
        except Exception, e:
            print "Failure: hosts not added into group--", e
            return

        print "Success: {0} added to group{1}".format(args[1:],gid)

    def do_addmbpolicy(self, line):
        """Add dynamic mb for an mb
           Usage: addmbpolicy [groupid1] [groupid2] [mbname] [dynamicmb]"""      
	args = line.split()
        if len(args) !=4:
            print "Invalid syntax"
            return
	str1="INSERT INTO MB_policy values({0},{1},'{2}','{3}');".format(args[0],args[1],args[2],args[3])
					
        try:
            self.db.cursor.execute(str1)
        except Exception, e:
            print "Failure: policy not added --", e
            return

        print "Success: (gid{0} gid{1} {2} {3})added to mbpolicy".format(args[0],args[1],args[2],args[3])

    def do_addlabel(self, line):
        """Add label for an mb
           Usage: addlabel [fid] [currentMB] [label]"""      
	args = line.split()
        if len(args) !=3:
            print "Invalid syntax"
            return
	str1="INSERT INTO FLH values({0},'{1}',{2});".format(args[0],args[1],args[2])
					
        try:
            self.db.cursor.execute(str1)
        except Exception, e:
            print "Failure: label not added --", e
            return

        print "Success: {0} has added label {1} to fid{2}".format(args[1],args[2],args[0])

    def do_addflow(self, line):
        """Add flow
           Usage: addflow [host1] [host2]"""      
	args = line.split()
        if len(args) !=2:
            print "Invalid syntax"
            return
	src = self._getHostId(args[0])
        if src is None:
        	return
	dst = self._getHostId(args[1])
        if dst is None:
        	return
					
        try:
            # get next flow id
            self.db.cursor.execute("SELECT * FROM drm;")
            fid = len(self.db.cursor.fetchall()) + 1
            self.db.cursor.execute("INSERT INTO drm (fid, src, dst) "
                                   "VALUES ({0}, {1}, {2});"
                                   .format(fid, src, dst))
        except Exception, e:
            print "Failure: flow not installed --", e
            return

        print "Success: installed flow with fid",fid


    def do_delviolation(self, line):
        """Delete dpga violations"
           Usage: delviolation"""
        args = line.split()
        if len(args) !=0:
            print "Invalid syntax"
            return
       
	try:
            self.db.cursor.execute("delete FROM dpga_violation;")
        except Exception, e:
            print "Failure:violation(s) not removed --", e
            return

        print "Success: remove all violations"

shortcut = "dpga"
description = "dynamic middlebox policy"
console = DpgaConsole
