"""
Routing sub-shell.
"""

from ravel.app import AppConsole
from ravel.log import logger

class RoutingConsole(AppConsole):
    def do_addflow(self, line):
        """Add a flow between two hosts, using Mininet hostnames
           Usage: addflow [host1] [host2] [opt:fw0[,fw1[,fw2[,lb0[,lb1]]]]]"""
        args = line.split()
        if len(args) != 2 and len(args) != 3 :
            print "Invalid syntax"
            return

        hostnames = self.env.provider.cache_name
        src = args[0]
        dst = args[1]
        if src not in hostnames:
            print "Unknown host", src
            return

        if dst not in hostnames:
            print "Unknown host", dst
            return
 	
        if len(args) == 3:
		mb=args[2].split(',')
		if len(mb)>0:
			for i in range(len(mb)):
				if mb[i]!='fw0' and mb[i]!='fw1' and mb[i]!='fw2' and mb[i]!='lb0' and mb[i]!='lb1' :
					print "Unknown middlebox"
					return

        src = hostnames[src]
        dst = hostnames[dst]
        try:
            # get next flow id
            self.db.cursor.execute("SELECT * FROM rm;")
            fid = len(self.db.cursor.fetchall()) + 1
            self.db.cursor.execute("INSERT INTO rm (fid, src, dst) "
                                   "VALUES ({0}, {1}, {2});"
                                   .format(fid, src, dst))
	    if len(args) == 3:
	    	for i in range(len(mb)):
            		self.db.cursor.execute("UPDATE rm set {0} = 1 where fid = {1};".format(mb[i], fid))
        except Exception, e:
            print "Failure: flow not installed --", e
            return

        print "Success: installed flow with fid", fid

    def _delFlowByName(self, src, dst):
        hostnames = self.env.provider.cache_name

        if src not in hostnames:
            print "Unknown host", src
            return

        if dst not in hostnames:
            print "Unknown host", dst
            return

        src = hostnames[src]
        dst = hostnames[dst]
        self.db.cursor.execute("SELECT fid FROM rm WHERE src={0} and dst={1};"
                               .format(src, dst))
        result = self.db.cursor.fetchall()

        if len(result) == 0:
            logger.warning("no flow installed for hosts {0},{1}".format(src, dst))
            return None

        fids = [res[0] for res in result]
        for fid in fids:
            self._delFlowById(fid)

        return fids

    def _delFlowById(self, fid):
        try:
            # does the flow exist?
            self.db.cursor.execute("SELECT fid FROM rm WHERE fid={0}".format(fid))
            if len(self.db.cursor.fetchall()) == 0:
                logger.warning("no flow installed with fid %s", fid)
                return None

            self.db.cursor.execute("DELETE FROM rm WHERE fid={0}".format(fid))
            return fid
        except Exception, e:
            print e
            return None

    def do_delflow(self, line):
        """Delete a flow between two hosts, using flow ID or Mininet hostnames"
           Usage: delflow [host1] [host2]
                  delflow [flow id]"""
        args = line.split()
        if len(args) == 1:
            fid = self._delFlowById(args[0])
        elif len(args) == 2:
            fid = self._delFlowByName(args[0], args[1])
        else:
            print "Invalid syntax"
            return

        if fid is not None:
            print "Success: removed flow with fid", fid
        else:
            print "Failure: flow not removed"

shortcut = "rt"
description = "IP routing"
console = RoutingConsole
