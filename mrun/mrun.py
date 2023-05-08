#!/usr/bin/env python3

import os, sys, getpass, getopt, csnobfuscate, csnremote, socket, csnresources, csnconfig

tokens       = []
lineNumber   = 1
fileName     = "stdin"
symbolTable  = {}
debugging    = False
verbose      = False
doLookupOnly = False
doNameserver = False
processorIds = {}
nisPassword  = ""

#
#  syntaxError - issues a syntax error and exits.
#

def syntaxError(message):
    global fileName, lineNumber
    print ("%s:%d:%s" % (fileName, lineNumber, message))
    sys.exit(1)


#
#  pushTokens - pushes a list of tokens after it has tokenised them
#

def pushTokens (lines):
    global tokens
    for line in lines:
        line = line.rstrip()
        line = line.split("#")[0]
        line = " " + line + " <lf>"
        line = line.replace(" ; ", " <;> ")
        line = line.replace(" for ", " <for> ")
        line = line.replace(" par ", " <par> ")
        line = line.replace(" end ", " <end> ")
        line = line.replace(" in ", " <in> ")
        line = line.replace(" to ", " <to> ")
        line = line.replace(" do ", " <do> ")
        line = line.replace(" by ", " <by> ")
        line = line.replace(" debug ", " <debug> ")
        line = line.replace(" timeout ", " <timeout> ")
        line = line.replace(" terminal ", " <terminal> ")
        line = line.replace(" processor ", " <processor> ")
        tokens += line.split()


#
#  readFile - read in, name, convert it to a list of lines
#             and pass them to pushTokens.
#

def readFile (name):
    try:
        pushTokens(open(name).readlines())
    except:
        print ("unable to open file", name)
        sys.exit(1)


#
#  getToken - returns the first token from the token stream.
#

def getToken():
    global tokens, lineNumber
    if len(tokens)>0:
        token = tokens[0]
        tokens = tokens[1:]
    else:
        token = "<eof>"
    if token == "<lf>":
        lineNumber += 1
        return getToken()
    if debugging:
        print ("<<", token, ">>", tokens)
    return token


#
#  isToken - tests whether we can see, token, in the list of
#            tokens.
#

def isToken(token):
    global tokens, lineNumber
    if len(tokens) == 0:
        return token == "<eof>"
    else:
        if tokens[0] == "<lf>":
            lineNumber += 1
            tokens = tokens[1:]
            return isToken(token)
        if debugging:
            print (tokens)
            print ("testing whether", tokens[0], " == ", token, tokens[0] == token)
        return tokens[0] == token


#
#  eat - consume a token and return True if the token
#        matched the current token.  It does not consume
#        a token if it did not match.
#

def eat(token):
    global tokens
    if isToken(token):
        getToken()
        if debugging:
            print ("eat returning True, having found", token)
        return True
    else:
        if debugging:
            print ("eat returning False, having failed to find", token, "token is actually", tokens[0])
        return False


#
#  insist - consumes, token, from the token list and
#           generates an error message if this token
#           was not seen.
#

def insist(token):
    if debugging:
        print ("insisting on", token)
    if not eat(token):
        syntaxError("missing " + token)


def setValue(var, value):
    global symbolTable
    symbolTable[var] = value


def getValue(var):
    global symbolTable
    if symbolTable.has_key(var):
        return symbolTable[var]
    else:
        syntaxError("variable " + var + " is unknown")


#
#  getFactor - handle unary '-'
#

def getFactor():
    if eat("<(>"):
        e = getExpr()
        insist("<)>")
        return e
    e = getToken()
    if (e[0] == '{') and (e[-1] == '}'):
        return int(getValue(e[1:-1]))
    else:
        return int(e)


#
#  getTerm -
#

def getTerm():
    v = getFactor()
    while isToken('<*>') or isToken('</>'):
        if eat('</>'):
            v /= getFactor()
        elif eat('<*>'):
            v *= getFactor()
    return v


#
#  getExpr - return an expression after evaluating all terms.
#

def getExpr():
    v = getTerm()
    while isToken('<+>') or isToken('<->'):
        if eat('<+>'):
            v += getTerm()
        elif eat('<->'):
            v -= getTerm()
    return v


#
#  getExpression - returns a string containing the expression
#                  found in the token stream.
#

def getExpression():
    global tokens
    e = getToken()
    if debugging:
        print (e)
    if (e[0] == '"') or (e[0] == "'"):
        return e[1:]
    if not (e[0] in '{-+(0123456789'):
        if debugging:
            print ("not an arithmetic expression")
        return e
    oldTokens = tokens
    e = e.replace('/', ' </> ')
    e = e.replace('*', ' <*> ')
    e = e.replace('+', ' <+> ')
    e = e.replace('-', ' <-> ')
    e = e.replace('(', ' <(> ')
    e = e.replace(')', ' <)> ')
    tokens = e.split()
    e = getExpr()
    tokens = oldTokens
    return str(e)


#
#  getVar - returns a variable, it checks to see that the variable is not
#           currently in use.
#

def getVar():
    global symbolTable
    var = getToken()
    if symbolTable.has_key(var):
        syntaxError("variable " + var + " is already in use in an outer for loop")
    else:
        return var


#
#  remove - remove a variable from the symbol table.
#

def remove(var):
    global symbolTable
    if symbolTable.has_key(var):
        del symbolTable[var]
    else:
        syntaxError("internal error: variable " + var + " is unknown and cannot be removed")


#
#  parseFor
#

def parseFor ():
    global symbolTable, tokens

    insist("<for>")
    var = getVar()
    insist("<in>")
    begin = getExpression()
    insist("<to>")
    end = getExpression()
    if eat("<by>"):
        by = int(getExpression())
    else:
        by = 1
    insist("<do>")
    if int(end) < int(begin):
        print ("the lower bound of the for loop must be less than equal to the higher bound")
        sys.exit(1)
    lookStart = tokens
    for i in range(int(begin), int(end)+1, by):
        tokens = lookStart
        setValue(var, str(i))
        parseStatementSequence()
    insist("<end>")
    remove(var)


#
#  getId - returns the processor name or id used to prefix each line of output.
#

def getId():
    return getExpression()


#
#  getUser - returns the user, password and directory of the executable.
#

def getUser():
    global nisPassword

    upd = getToken()
    if (len(upd)>2) and (upd[0] == '[') and (upd[-1] == ']'):
        l=upd[1:-1].split(':')
        if len(l) == 3:
            u,p,d = l
            u = u.rstrip()
            p = p.rstrip()
            d = d.rstrip()
            if u == "":
                u = getpass.getuser()
            if d == "":
                d = os.getcwd()
            if p == "":
                if nisPassword == "":
                    nisPassword = csnobfuscate.encode(getpass.getpass())
                p = nisPassword
            return u,p,d
        else:
            syntaxError("expecting [username:password:directory] separated by two colons")
    else:
        syntaxError("expecting [username:password:directory]")


#
#  getMachine - returns the machine name
#

def getMachine():
    machineName = getToken()
    if (len(machineName)>2) and (machineName[0]=='(') and (machineName[-1]==')'):
        return csnresources.lookupMachine(machineName[1:-1], syntaxError)
    return machineName


#
#  getCommand - returns the command string
#

def getCommand():
    command = ""
    while not isToken("<;>"):
        if command != "":
            command += " "
        command += getExpression()
    return command


#
#  parseProcessor - parse the processor line
#

def parseProcessor():
    global debugging, verbose, doNameserver
    if debugging:
        print ("parseProcessor")
    insist("<processor>")
    id = getId()
    machine = getMachine()
    user, password, dir = getUser()
    command = getCommand()
    if verbose:
        print ("processor %s     ssh %s@%s -p %s %s" % (id, user, machine, password, command))
    insist("<;>")
    if processorIds.has_key(id):
        syntaxError('processor ' + id + ' has already been defined')
    t = csnremote.remoteThread (id, machine, command, socket.getfqdn(),
                                dir, user, csnobfuscate.decode(password),
                                False, False, debugging, False, doNameserver)
    csnremote.registerThread (t)
    processorIds[id] = t


#
#  parseStatementSequence - parse processor or for statements.
#

def parseStatementSequence():
    if debugging:
        print ("parseStatementSequence")
    if isToken("<processor>"):
        parseProcessor()
    elif isToken("<for>"):
        parseFor()


#
#  parseTimeout
#

def parseTimeout():
    global verbose

    if debugging:
        print ("parseTimeout")
    value = getToken()
    if debugging:
        print ("value is", value)
    insist("<;>")
    if value[-1] == 's':
        seconds = int(value[:-1])
    elif value[-1] == 'm':
        seconds = int(value[:-1])*60
    elif value[-1] == 'h':
        seconds = int(value[:-1])*60*60
    elif value[-1] == 'd':
        seconds = int(value[:-1])*60*60*24
    else:
        syntaxError("you must specify the units of time in the timeout 's', 'm', 'h' or 'd'")
    if verbose:
        print ("timeout is", seconds, "seconds")


#
#  parseTerminal - get a list of all processors which need to run in
#                  separate terminals.
#

def parseTerminal():
    global verbose, processorIds

    if debugging:
        print ("parseTerminal")
    while not isToken("<;>"):
        name = getToken()
        if processorIds.has_key(name):
            processorIds[name].setWindow(True)
            if verbose:
                print ("running processor", name, "in a window")
        else:
            syntaxError('no such processor "' + name + '"')
    insist("<;>")


#
#  getString - returns string, s, after checking whether it is a variable.
#

def getString(s):
    global symbolTable
    if (s[0] == '{') and (s[-1] == '}') and (len(s)>2):
        return getValue(s[1:-1])
    else:
        return s


#
#  fixupCommand - alter the command line for each of the debugged
#                 threads
#

def fixupCommand(debugList, newCommandLine):
    global processorIds, verbose
    for p in debugList:
        if processorIds.has_key(p):
            id = processorIds[p]
            oldCommandLine = id.getCommand().split()
            if len(oldCommandLine)>0:
                setValue('program', oldCommandLine[0])
            if len(oldCommandLine)>1:
                setValue('argv', oldCommandLine[1:])
            commandLine = ""
            for w in newCommandLine.split():
                commandLine += " " + getString(w)
            commandLine = commandLine.strip()
            if len(oldCommandLine)>0:
                remove('program')
            if len(oldCommandLine)>1:
                remove('argv')
            if verbose:
                print ("debug processor", p, "with", commandLine)
            id.setCommand(commandLine)
            id.setDebug(True)
        else:
            syntaxError("no known processor " + p)


#
#  parseDebug - get a list of all processors which are to be debugged.
#

def parseDebug():
    global verbose

    if debugging:
        print ("parseDebug")
    newCommandLine = ""
    while not isToken("<processor>"):
        if newCommandLine == "":
            newCommandLine = getToken()
        else:
            newCommandLine += " " + getToken()
    insist("<processor>")
    debugList = []
    while not isToken("<;>"):
        debugList += [getToken()]
    insist("<;>")
    fixupCommand(debugList, newCommandLine)


#
#  parseStatements - parse the
#                       timeout
#                       debug
#                       terminal
#                    statements
#

def parseStatements():
    if debugging:
        print ("parseStatements")
    if eat("<timeout>"):
        parseTimeout()
    elif eat("<debug>"):
        parseDebug()
    elif eat("<terminal>"):
        parseTerminal()
    else:
        syntaxError("expecting timeout or debug or terminal statement")


#
#  parseFile -
#

def parseFile():
    if eat("<par>"):
        if debugging:
            print ("par statement")
        while isToken("<processor>") or isToken("<for>"):
            parseStatementSequence()
        if debugging:
            print ("end statement")
        insist("<end>")
        while isToken("<terminal>") or isToken("<debug>") or isToken("<timeout>"):
            parseStatements()

#
#  usage - displays minimal help.
#

def usage():
    print ("usage:  mrun [-h][-v][-d][-p][-L] [-f filename]")
    print ("        -h   help.")
    print ("        -v   verbose, display all ssh commands.")
    print ("        -d   turn on mrun internal debugging.")
    print ("        -p   prompt user for a password and obfuscates it.")
    print ("        -f   filename.  Use filename for input.")
    print ("        -L   display all the available processors.")
    sys.exit(0)


#
#  setupNameserver
#

def setupNameserver():
    global debugging
    csnremote.registerThread(csnremote.remoteThread("ns", "localhost", "csnnameserver", socket.gethostname(),
                                                    csnconfig.BINDIR,
                                                    "", "",
                                                    False, False, debugging, True, True))


#
#  main - the main function.
#

def main():
    global tokens, fileName, debugging, verbose, doLookupOnly, doNameserver
    doObfuscate = False
    try:
        optlist, list = getopt.getopt(sys.argv[1:], ':df:hnpLv')
        for opt in optlist:
            if opt[0] == '-h':
                usage()
            if opt[0] == '-f':
                fileName = opt[1]
            if opt[0] == '-v':
                verbose = True
            if opt[0] == '-d':
                debugging = True
            if opt[0] == '-n':
                doNameserver = True
            if opt[0] == '-p':
                doObfuscate = True
            if opt[0] == '-L':
                doLookupOnly = True
    except:
        usage()
    csnresources.populate()
    if doLookupOnly:
        csnresources.printResources()
        sys.exit(0)
    if doObfuscate:
        csnobfuscate.makePassword()
        sys.exit(0)
    readFile(fileName)
    if debugging:
        print (tokens)
    if doNameserver:
        setupNameserver()
    parseFile()
    csnremote.runThreads (verbose)

main()
