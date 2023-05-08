#!/usr/bin/env python3

import getpass, base64, sys


def encode (password):
    #Encode 3 times
    password = password.rstrip ()
    encoded = base64.b16encode (base64.b64encode (base64.b64encode (password.encode ('utf-8')))).decode ('utf-8')
    i = 0
    password = ''
    while i < len(encoded):
        if len(password) == 0:
            password = encoded[0:4]
        else:
            password = password + '-' + encoded[i:4 + i]
        i += 4;
    return password

def decode (password):
    password = password.rstrip ()
    password = password.replace ('-', '')
    return base64.b64decode (base64.b64decode (base64.b16decode (password.encode ('utf-8')))).decode ('utf-8')

def makePassword():
    pw = getpass.getpass ("Enter password to obfuscate: ")
    encoded = encode (pw)
    decoded = decode (encoded)
    print ("obfuscated password: " + encoded)
    if decode (encoded) != pw:
        print ("error cannot decode obfuscated version..")
        sys.exit (1)
