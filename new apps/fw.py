import cmd
from ravel.app import AppConsole

class FirewallConsole(AppConsole):
    def _getHostId(self, hname):
        hostnames = self.env.provider.cache_name
        if hname not in hostnames:
            print "Unknown host", hname
            return None

        return hostnames[hname]

    def do_addhost(self, line):
        """Add a host to the whitelist
           Usage: addhost [fwname] [hostname]"""
        args = line.split()
        if len(args) != 2:
            print "Invalid syntax"
            return
	fwid=0
	if args[0]=='fw0':
		fwid=0
	elif args[0]=='fw1':
		fwid=1
	elif args[0]=='fw2':
		fwid=2
	else:
		print "Invalid syntax"
		return
        hostid = self._getHostId(args[1])
        if hostid is None:
            return

        try:
            self.db.cursor.execute("INSERT INTO FW{0}_policy_user VALUES ({1});"
                                   .format(fwid,hostid))
        except Exception, e:
            print "Failure: host not added --", e
            return

        print "Success: host {0} added to FW{1}'s whitelist".format(hostid,fwid)

    def do_delhost(self, line):
        """Remove a host from the whitelist
           Usage: delhost [fwname] [hostname]"""
        args = line.split()
        if len(args) != 2:
            print "Invalid syntax"
            return
	fwid=0
	if args[0]=='fw0':
		fwid=0
	elif args[0]=='fw1':
		fwid=1
	elif args[0]=='fw2':
		fwid=2
	else:
		print "Invalid syntax"
		return
        hostid = self._getHostId(args[1])
        if hostid is None:
            return

        try:
            self.db.cursor.execute("DELETE FROM FW{0}_policy_user WHERE uid={1};"
                                   .format(fwid,hostid))
        except Exception, e:
            print "Failure: host not removed --", e
            return

        print "Success: host {0} removed from FW{1}'s whitelist".format(hostid,fwid)

    def do_addflow(self, line):
        """Add a flow to the whitelist
           Usage: addflow [fwname] [hostname1] [hostname2]"""
        args = line.split()

        if len(args) != 3:
            print "Invalid syntax"
            return
	fwid=0
	if args[0]=='fw0':
		fwid=0
	elif args[0]=='fw1':
		fwid=1
	elif args[0]=='fw2':
		fwid=2
	else:
		print "Invalid syntax"
		return
        src = self._getHostId(args[1])
        dst = self._getHostId(args[2])
        if src is None or dst is None:
            return

        try:
            self.db.cursor.execute("INSERT INTO FW{0}_policy_acl VALUES "
                                   "({1},{2},1);"
                                   .format(fwid,src, dst));
        except Exception, e:
            print "Failure: flow not added --", e
            return

        print "Success: flow ({0},{1}) added to FW{2}'s whitelist".format(src, dst,fwid)

    def do_delflow(self, line):
        """Remove a flow from the whitelist
           Usage: delflow [fwname] [hostname1] [hostname2]"""
        args = line.split()
        if len(args) != 3:
            print "Invalid syntax"
            return
	fwid=0
	if args[0]=='fw0':
		fwid=0
	elif args[0]=='fw1':
		fwid=1
	elif args[0]=='fw2':
		fwid=2
	else:
		print "Invalid syntax"
		return

        src = self._getHostId(args[1])
        dst = self._getHostId(args[2])
        if src is None or dst is None:
            return

        try:
            self.db.cursor.execute("DELETE FROM FW{0}_policy_acl VALUES WHERE "
                                   "end1={1} AND end2={2};"
                                   .format(fwid,src, dst));
        except Exception, e:
            print "Failure: flow not removed --", e
            return

        print "Success: flow ({0},{1}) removed from FW{2}'s whitelist".format(src, dst,fwid)

shortcut = "fw"
description = "a stateful firewall application"
console = FirewallConsole
