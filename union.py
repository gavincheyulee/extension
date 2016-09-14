#!/usr/bin/env python
#
# Irrelevance reasoning configuration generator
#
# Running no params is equivalent to generating
# a fattree topology with 8 pods, 10 FWs, and 10 NATs
# where the FW will block 20% of possible host (src,dst) combinations:
#    ./irreasoning.py --toposize 8 --fw 10 --nat 10 --blockrate 0.2
import shutil
import datetime
import os
import random
import sys
import struct
import socket
import networkx

from optparse import OptionParser

def next_ip(base, offset):
    ipint = struct.unpack('!I', socket.inet_aton(base))[0]
    ipint += offset
    ip = socket.inet_ntoa(struct.pack('!I', ipint))
    return ip

class Configuration(object):
    def __init__(self, clients, servers, fw, nat, nat_memberships, topo):
        # a list of clients by hostname
        self.clients = clients

        # a list of servers by hostname
        self.servers = servers

        # a dictionary of FW instance IDs and the flows it manages/blacklists
        self.fw = fw

        # a dictionary of NAT instance IDs and the public IP it manages
        self.nat = nat

        # a dictionary of NAT instance IDs and the hostnames beloning to that
        # instance/public IP
        self.nat_memberships = nat_memberships

        # the topology
        self.topo = topo

    def insert_config(self):
        print "start to test"
        print "\n"
        print "#" * 40
        print "# NAT Members"
        print "# format: service_id hostname host_ip"
        print "#" * 40
        for natid, members in self.nat_memberships.iteritems():
            for member in members:
                print natid, member, self.topo.hosts[member].ip

        print "\n\n"
        print "#" * 40
        print "# FW: Blacklisted Flows "
        print "# format: fw_id src dst"
        print "#" * 40
        for i, flows in self.fw.iteritems():
            for flow in flows:
                print i, flow[0], flow[1]
        print '\n' 
        print 'start insert test' 
        print '\n'       
        for natid, members in self.nat_memberships.iteritems():
            yicesinsertscript1 = '''(define X::int)
(define Y::int)
(define S::int)
(define T::int)
(assert (= Y T))
(assert (= X S))'''
            inatstatement1="(assert (or"
            inatstatement2=" (= X "
            inatstatement3=")"
            inatstatement4="))"
            inatstatement0=inatstatement1
            if len(members)==1:
                inatstatement0="(assert (= X "+str(members[0][1:])+"))"
            else:    
                for member in members:
                    inatstatement=inatstatement2+str(member[1:])+inatstatement3
                    inatstatement0=inatstatement0+inatstatement
                inatstatement0=inatstatement0+inatstatement4
            for i, flows in self.fw.iteritems():
                ifwstatement1="(assert (or"
                ifwstatement2=" (and"
                ifwstatement3=" (= S "
                ifwstatement4=") (= T "
                ifwstatement5="))"
                ifwstatement6="))"
                ifwstatement0=ifwstatement1
                if len(flows)==0:
                    ifwstatement0=""
                elif len(flows)==1:
                    fl=list(flows)
                    ifwstatement0="(assert (and (= S "+str(fl[0][0][1:])+") (= T "+str(fl[0][1][1:])+")))"
                else:
                    for flow in flows:
                        ifwstatement=ifwstatement2+ifwstatement3+str(flow[0][1:])+ifwstatement4+str(flow[1][1:])+ifwstatement5
                        ifwstatement0=ifwstatement0+ifwstatement
                    ifwstatement0=ifwstatement0+ifwstatement6   
                #print "\n"    
                #print members
                #print flows    
                #print natstatement0
                #print '\n'
                #print fwstatement0    
                yicesinsertscript=yicesinsertscript1+'\n'+inatstatement0+'\n'+ifwstatement0+'\n'+'(check)\n'+'(show-model)\n'
                #print yices_script
                yicesinsertfile="nattest.ys"
                fyices=open(yicesinsertfile,'w')
                fyices.write(yicesinsertscript)
                fyices.close()
                starttime = datetime.datetime.now()
                os.system("yices "+yicesinsertfile)
                endtime = datetime.datetime.now()
                ftxt=open("natinsert.txt",'a')
                t=(endtime - starttime).microseconds/1000 #millisecomd
                statement="NAT"+str(natid)+" and FW"+str(i)+" YICES execution time:"
                print statement+str(t)+'\n'
                ftxt.write('#'+statement+'\n')
                ftxt.write(str(t)+'\n')
                ftxt.close()

    def delete_config(self):
        print 'start delete test'
        print '\n'
        for i, flows in self.fw.iteritems():
            yicesdeletescript1 = '''(define X::int)
(define Y::int)
(define S::int)
(define T::int)
(assert (= Y T))'''
            dfwstatement1="(assert (or"
            dfwstatement2=" (and"
            dfwstatement3=" (= X "
            dfwstatement4=") (= Y "
            dfwstatement5="))"
            dfwstatement6="))"
            dfwstatement0=dfwstatement1
            if len(flows)==0:
                dfwstatement0=""
            elif len(flows)==1:
                fl=list(flows)
                dfwstatement0="(assert (and (= X "+str(fl[0][0][1:])+") (= Y "+str(fl[0][1][1:])+")))"
            else:
                for flow in flows:
                    dfwstatement=dfwstatement2+dfwstatement3+str(flow[0][1:])+dfwstatement4+str(flow[1][1:])+dfwstatement5
                    dfwstatement0=dfwstatement0+dfwstatement
                dfwstatement0=dfwstatement0+dfwstatement6
            for natid, members in self.nat_memberships.iteritems():
                dnatstatement1="(assert (or"
                dnatstatement2=" (= T "
                dnatstatement3=")"
                dnatstatement4="))"
                dnatstatement0=dnatstatement1
                if len(members)==1:
                    dnatstatement0="(assert (= T "+str(members[0][1:])+"))"
                else:    
                    for member in members:
                        dnatstatement=dnatstatement2+str(member[1:])+dnatstatement3
                        dnatstatement0=dnatstatement0+dnatstatement
                    dnatstatement0=dnatstatement0+dnatstatement4
                yicesdeletescript=yicesdeletescript1+'\n'+dfwstatement0+'\n'+dnatstatement0+'\n'+'(check)\n'+'(show-model)\n'
                #print yicesdeletescript
                yicesfile="fwtest.ys"
                fyices=open(yicesfile,'w')
                fyices.write(yicesdeletescript)
                fyices.close()
                starttime = datetime.datetime.now()
                os.system("yices "+yicesfile)
                endtime = datetime.datetime.now()
                ftxt=open("fwdelete.txt",'a')
                t=(endtime - starttime).microseconds/1000 #millisecomd
                statement="FW"+str(i)+" and NAT"+str(natid)+" YICES execution time:"
                print statement+str(t)+'\n'
                ftxt.write('#'+statement+'\n')
                ftxt.write(str(t)+'\n')
                ftxt.close()                    



class Switch(object):
    def __init__(self, name, ip="10.1.0.0"):
        self.name = name
        self.ip = ip

    def __repr__(self):
        return str(self)

    def __str__(self):
        return "{0}: {1}".format(self.name, self.ip)

class Host(object):
    def __init__(self, name, ip="10.0.0.1"):
        self.name = name
        self.ip = ip

    def __repr__(self):
        return str(self)

    def __str__(self):
        return "{0}: {1}".format(self.name, self.ip)

class FattreeTopo(object):
    def __init__(self, k=8):
        self.size = k
        self.hosts = {}
        self.switches = {}
        self.links = set()
        self._build()

    def _build(self):
        cores = (self.size/2)**2
        aggs = (self.size/2) * self.size
        edges = (self.size/2) * self.size
        hosts = (self.size/2)**2 * self.size
        switch_base = "172.0.0.1"
        host_base = "10.0.0.1"

        for pod in range(0, self.size):
            agg_offset = cores + self.size/2 * pod
            edge_offset = cores + aggs + self.size/2 * pod
            host_offset = cores + aggs + edges + (self.size/2)**2 * pod

            for agg in range(0, self.size/2):
                core_offset = agg * self.size/2
                aggname = "s{0}".format(agg_offset + agg)
                ip = next_ip(switch_base, agg_offset + agg)
                self.switches[aggname] = Switch(aggname, ip)

                # connect core and aggregate switches
                for core in range(0, self.size/2):
                    corename = "s{0}".format(core_offset + core)
                    ip = next_ip(switch_base, core_offset + core)
                    self.switches[corename] = Switch(corename, ip)
                    self.links.add((corename, aggname))
                    self.links.add((aggname, corename))

                # connect aggregate and edge switches
                for edge in range(0, self.size/2):
                    edgename = "s{0}".format(edge_offset + edge)
                    ip = next_ip(switch_base, edge_offset + edge)
                    self.switches[edgename] = Switch(edgename, ip)
                    self.links.add((edgename, aggname))
                    self.links.add((aggname, edgename))

            # connect edge switches with hosts
            for edge in range(0, self.size/2):
                edgename = "s{0}".format(edge_offset + edge)

                for h in range(0, self.size/2):
                    hostname = "h{0}".format(host_offset + self.size/2 * edge + h)
                    ip = next_ip(host_base, host_offset + self.size/2 * edge + h)
                    self.hosts[hostname] = Host(hostname, ip)
                    self.links.add((hostname, edgename))
                    self.links.add((edgename, hostname))

topos = { 'fattree' : FattreeTopo }

def optParser():
    desc = "Ravel Irrelevance Reasoning Configuration Generator"
    usage = "%prog [options]\ntype %prog -h for details"

    parser = OptionParser(description=desc, usage=usage)
    parser.add_option("--toposize", "-t", type="string", default=8,
                      help="Number of fattree pods (default: 8)")
    parser.add_option("--fw", "-f", type="string", default=10,
                      help="Number of FW instance (default: 10)")
    parser.add_option("--nat", "-n", type="string", default=10,
                      help="Number of NAT instances (default: 10)")
    parser.add_option("--blockrate", "-b", type="string", default=0.05,
                      help="Percentage of node pairs to block with FW (default 0.05)")

    return parser

def assign_fw_flows_global(num_fw, flows):
    flow_map = {}
    rev_flow_map = {}
    for end1, end2 in flows:
        if end1 not in flow_map:
            flow_map[end1] = []

        if end2 not in rev_flow_map:
            rev_flow_map[end2] = []

        flow_map[end1].append(end2)
        rev_flow_map[end2].append(end1)

    g = networkx.Graph()
    for end1, end2 in flows:
        g.add_edge(end1, end2)

    subgraphs = networkx.connected_component_subgraphs(g)
    divisions = {}
    for i, subgraph in enumerate(subgraphs):
        div_id = len(divisions) % num_fw
        if div_id not in divisions:
            divisions[div_id] = set()

        for node in subgraph.nodes():
            if node in flow_map:
                for end2 in flow_map[node]:
                    divisions[div_id].add((node, end2))

            if node in rev_flow_map:
                for end1 in rev_flow_map[node]:
                    divisions[div_id].add((end1, node))

    return divisions

def assign_fw_flows(num_fw, blockrate, servers, clients):
    per_fw_count = int(len(servers) * len(clients) * blockrate / num_fw)
    divisions = {}
    for i in range(num_fw):
        divisions[i] = [[], []]

    for i, server in enumerate(servers):
        divisions[i % num_fw][0].append(server)

    for i, client in enumerate(clients):
        divisions[i % num_fw][1].append(client)

    blacklist = {}
    for i in range(num_fw):
        blacklist[i] = set()

        while len(blacklist[i]) < per_fw_count:
            s = random.choice(divisions[i][0])
            c = random.choice(divisions[i][1])
            blacklist[i].add((s,c))

    return blacklist

def generate(toposize=8, num_fw=4, num_nat=4, blockrate=0.05):
    toposize = int(toposize)
    num_fw = int(num_fw)
    num_nat = int(num_nat)
    blockrate = float(blockrate)

    topo = FattreeTopo(k=toposize)
    servers = []
    clients = []

    # deterministically assign hosts to server or client role
    for i, host in enumerate(topo.hosts.keys()):
        if i % 2 == 0:
            servers.append(host)
        else:
            clients.append(host)

    if len(clients) < num_fw:
        print "ERROR: #clients < #fw, increase topology size"
        sys.exit(0)

    nat = {}
    nat_members = {}

    public_ipbase = "192.0.0.1"
    for i in range(num_nat):
        nat[i] = next_ip(public_ipbase, i)
        nat_members[i] = []

    # deterministically assign servers to a NAT ID (ie, a service)
    for i, host in enumerate(servers):
        groupid = i % num_nat
        nat_members[groupid].append(host)

    # generate all possible (client, server) flows
    # flows = []
    # for server in servers:
    #     for client in clients:
    #         flows.append((server, client))
    # blacklist a random sample of those flows
    # blacklist = random.sample(flows, int(len(flows) * blockrate))
    # fw_divisions = assign_fw_flows(num_fw, blacklist)
    fw_divisions = assign_fw_flows(num_fw, blockrate, servers, clients)

    config1 = Configuration(clients, servers, fw_divisions, nat, nat_members, topo)
    config1.insert_config()
    yicesdata1="insert_toposize_"+str(toposize)+"_natnum_"+str(num_nat)+"_fwnum_"+str(num_fw)
    shutil.copyfile("natinsert.txt",yicesdata1+".txt")
    open("natinsert.txt","w").close()
    config2 = Configuration(clients, servers, fw_divisions, nat, nat_members, topo)
    config2.delete_config()
    yicesdata2="delete_toposize_"+str(toposize)+"_fwnum_"+str(num_fw)+"_natnum_"+str(num_nat)
    shutil.copyfile("fwdelete.txt",yicesdata2+".txt")
    open("fwdelete.txt","w").close()
    return config1,config2

if __name__ == "__main__":
    parser = optParser()
    opts, args = parser.parse_args()
    if args:
        parser.print_help()
        sys.exit(0)

    generate(opts.toposize, opts.fw, opts.nat, opts.blockrate)