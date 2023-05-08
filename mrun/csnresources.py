#!/usr/bin/env python3

#
# opens up /etc/csn.conf and reads the list of machines it probes
# these machines to ensure that ssh is available before adding them to
# an architectures dictionary.
#

import os, sys, socket, random, copy
from socket import *

SSHPORT = 22
PortTimeout = 10.0   # seconds before timing out testing whether a ssh service exists
processors = {}
available = {}
debugging = False


#
#  readCsnConf - returns the csn.conf file as a list of lines.
#

def readCsnConf ():
    home = os.getenv("HOME", None)
    if home and os.path.exists(os.path.join(home, 'csn.conf')):
        return open(os.path.join(home, 'csn.conf'), 'r').readlines()
    elif os.path.exists('/etc/csn.conf'):
        return open('/etc/csn.conf', 'r').readlines()
    else:
        print ("cannot read /etc/csn.conf, is the csn package installed?")
        sys.exit(1)


#
#  scanMachine - tests port, 22, and if ssh exists adds an entry into the dictionary
#

def scanMachine (arch, machine):
    global SSHPORT, PortTimeout, processors
    s = socket(AF_INET, SOCK_STREAM)
    # s.setblocking(0)
    s.settimeout(PortTimeout)
    if s.connect_ex((machine, SSHPORT)) == 0:
        if arch in processors:
            processors[arch] += [machine]
        else:
            processors[arch] = [machine]
    s.close()


#
#  scanRange - scans a range of machines denoted by [nn-mm]
#

def scanRange (arch, machine, line):
    l = machine.split('[')[0]
    r = machine.split(']')[1]
    low = machine.split('[')[1].split('-')[0]
    high = machine.split('[')[1].split('-')[1].split(']')[0]
    if len(machine.split('[')) > 2:
        print (l)
        print ("can only have one range per machine in csn.conf", machine)
        sys.exit(1)
    n = len(low)
    if n != len(high):
        print (l)
        print ("the low and high range must occupy the same number of characters", machine)
        sys.exit(1)
    format = "%d" % n
    for i in range(int(low), int(high)+1):
        host = ("%s%0" + format + "d%s") % (l, i, r)
        scanMachine(arch, host)


#
#  scanMachines - scan a list of machines
#

def scanMachines (arch, line):
    for m in line.split():
        if m != "":
            if '[' in m:
                scanRange(arch, m, line)
            else:
                scanMachine(arch, m)


#
#  lookupMachine - given an architecture, arch, return
#                  a machinename
#

def lookupMachine (arch, syntaxError):
    global processors, available, debugging
    if arch in processors:
        if debugging:
            print (available[arch])
            print (processors[arch])
        if available[arch] == []:
            available[arch] = copy.deepcopy(processors[arch])
        choice = random.choice(available[arch])
        available[arch].remove(choice)
        return choice
    else:
        syntaxError("unknown architecture " + arch)


#
#  populate - populate the architectures dictionary based on /etc/csn.conf
#             or a local csn.conf in the users top level directory.
#

def populate ():
    global processors, available

    for c in readCsnConf():
        l = c.split('#')[0]
        arch = l.split(':')[0].lstrip()
        if arch != "":
            scanMachines(arch, l.split(':')[1])
    available = copy.deepcopy(processors)


#
#  printResources - prints the contents of our processors dictionary.
#

def printResources ():
    for arch, machineList in processors.iteritems():
        print ("Processor pool", arch, "has", len(machineList), "available processors")
        i = 0
        for machine in machineList:
            if i % 2 == 0:
                print (" ")
                print ("   ", end="")
            print (machine, end="")
            i += 1
        print (" ")
