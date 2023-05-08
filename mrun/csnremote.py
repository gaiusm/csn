#!/usr/bin/env python3

import pexpect, os, select, time, string, sys, getpass

global_password = ""

def checkPassword (username, password):
    global global_password
    if password == "":
        if global_password == "":
            global_password = getpass.getpass(username + " please enter your password: ")
        return global_password
    else:
        return password


class remoteThread:
    #
    #  __init__:  create the object initialise all fields.
    #
    def __init__ (self,
                  name, machine, command, nsaddress,
                  directory, username, password,
                  window, debug, debugging,
                  nameserver, usenameserver):
        self.name = name
        self.isNameserver = False
        self.remoteMachine = machine
        self.command = command
        self.directory = directory
        self.username = username
        self.password = password
        self.nameserverAddress = nsaddress
        self.windowNeeded = window
        self.debuggerNeeded = debug
        self.debugging = debugging
        self.pending = ""
        self.isNameserver = nameserver
        self.useNameserver = usenameserver
    #
    #  doDebug - display all thread output as it comes to life if we are debugging.
    #
    def doDebug(self):
        if self.debugging:
            print (self.child.before, end="")
            print (self.child.after)
    #
    #  isTheNameserver - returns True if we are the nameserver
    #
    def isTheNameserver(self):
        return self.isNameserver
    #
    #  runCommand - start the thread, it maybe the nameserver in which case do not
    #               set the environment variable CSN_NAMESERVER.  If it is not
    #               the nameserver then ssh to the required machine, set env
    #               and run the program.
    #
    def runCommand(self):
        if self.isNameserver:
            print ("waiting for the nameserver to become available:", end="")
            while True:
                self.child = pexpect.spawn(os.path.join(self.directory, self.command))
                i = self.child.expect (['nameserver is ready', 'already in use', pexpect.EOF])
                if i==0:
                    print ("success")
                    return True
                elif (i==1) or (i==2):
                    if self.child.isalive():
                        self.child.terminate()
                    time.sleep(1)
                    print (".", end="")
                    file.flush(sys.stdout)
                    os.system("killall nameserver > /dev/null 2>&1")
                    time.sleep(1)
        else:
            self.password = checkPassword(self.username, self.password)
            os.system('ssh-keygen -R ' + self.remoteMachine + ' > /dev/null 2>&1 ')
            c = 'ssh -X %s@%s' % (self.username, self.remoteMachine)
            self.child = pexpect.spawn(c)
            while True:
                i = self.child.expect (['assword:', 'passphrase for key', 'yes/no', "\$", pexpect.EOF])
                self.doDebug()
                if i==0 or i==1:
                    self.child.sendline(self.password + "\r")
                elif i==2:
                    self.child.sendline("yes\r")
                elif i==3:
                    break;
                elif i==4:
                    print ("cannot log into %s@%s" % (self.username, self.remoteMachine))
                    return False
            if self.debugging:
                print ("cd " + self.directory + "\r")
            self.child.sendline("cd " + self.directory + "\r")
            i = self.child.expect (["\$", pexpect.EOF])
            self.doDebug()
            if i==1:
                print ("remote host has terminated the connection (%s@%s)" % (self.username, self.remoteMachine))
                return False
            if self.useNameserver:
                self.child.sendline("export CSN_NAMESERVER=" + self.nameserverAddress + "\r")
                i = self.child.expect (["\$", pexpect.EOF])
                if i==1:
                    print ("processor %s failed to set CSN_NAMESERVER" % (self.name))
                    return False
            self.doDebug()
            if self.windowNeeded:
                # c = 'gnome-terminal --command="env mrex %s" --title="%s"' % (self.command, self.name)
                c = 'mate-terminal --command="env mrex %s" --title="%s"' % (self.command, self.name)
                self.child.sendline(c + "\r")
                # print c
            else:
                self.child.sendline(self.command + "\r")
            return True
    #
    #  fileno - returns the file descriptor (used in select)
    #
    def fileno(self):
        return self.child.fileno()
    #
    #  checkRead - fd has data ready, read it and display it.
    #
    def checkRead(self, fd):
        if fd == self.fileno():
            chars = self.pending + self.child.read_nonblocking(8192)
            lines = string.split(chars, "\n")
            if lines != []:
                for line in lines[:-1]:
                    print ("<processor %s>:%s" % (self.name, line))
                self.pending = lines[-1]
            else:
                self.pending = chars
    #
    #  terminateCommand - shutdown thread.
    #
    def terminateCommand (self):
        if self.child.isalive ():
            self.child.sendcontrol('c')
            self.child.sendcontrol('\\')
            self.child.terminate ()
            self.child.close (True)
            self.child.wait ()
        else:
            print ("remote session", self.getName (), ": already terminated")
    #
    #  getName - return the name of the thread
    #
    def getName(self):
        return self.name
    #
    #  getCommand - return the command line for the thread
    #
    def getCommand(self):
        return self.command
    #
    #  setCommand - sets the command line for the thread
    #
    def setCommand(self,command):
        self.command = command
    #
    #  setDebug - this thread will be debugged.
    #
    def setDebug(self,value):
        self.debuggerNeeded = value
    #
    #  setWindow - this thread will be run in a gnome-terminal
    #
    def setWindow(self,value):
        self.windowNeeded = value

#
#  end of remoteThread class
#

allThreads = []

#
#  registerThread - remember a thread
#

def registerThread (t):
    global allThreads
    allThreads += [t]


#
#  runThreads - run each thread, finally kill them all off when the user
#               presses <enter>.
#

def runThreads(verbose):
    global allThreads

    for t in allThreads:
        if t.isTheNameserver():
            if verbose:
                print ("starting the nameserver")
            if not t.runCommand():
                print ("problem starting the name server")
                sys.exit(1)
        else:
            if verbose:
                print ("starting the thread", t.getName())
            if not t.runCommand():
                print ("%s: %s: failed to run" % (t.getName(), t.getCommand()))
                sys.exit(1)
    print ("press the <enter> key to terminate")
    finished = False
    while not finished:
        ifds = [sys.stdin.fileno()]
        for t in allThreads:
            ifds += [t.fileno()]
        ready = select.select(ifds, [], [])
        if ready[0] == []:
            finished = True
        for fd in ready[0]:
            if fd == sys.stdin.fileno():
                finished = True
            else:
                for t in allThreads:
                    t.checkRead(fd)
    print ("halting and tidying up..", end="")
    file.flush (sys.stdout)
    # print "allThreads =", allThreads
    for t in allThreads:
        t.terminateCommand ()
    print ("done")

#
#  test code.
#

if __name__ == "__main__":
    registerThread(remoteThread("ns", "localhost", "./nameserver", "localhost",
                                "/home/gaius/Sandpit/build-csn",
                                "gaius", "a", False, False, False, True, True))
    registerThread(remoteThread("0", "localhost", "./ex1", "localhost",
                                "/home/gaius/Sandpit/build-csn",
                                "gaius", "a", False, False, False, False, True))
    registerThread(remoteThread("1", "localhost", "./ex1 0", "localhost",
                                "/home/gaius/Sandpit/build-csn",
                                "gaius", "a", False, False, False, False, True))
    runThreads(False)
