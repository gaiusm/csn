(* Copyright (C) 2003 Free Software Foundation, Inc. *)
(* This file is part of GNU Modula-2.

GNU Modula-2 is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2, or (at your option) any later
version.

GNU Modula-2 is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License along
with gm2; see the file COPYING.  If not, write to the Free Software
Foundation, 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

IMPLEMENTATION MODULE csnsys ;

FROM Executive IMPORT DESCRIPTOR, SEMAPHORE,
                      InitProcess, Resume, Wait, Signal, InitSemaphore ;

FROM Debug IMPORT Halt ;
FROM sckt IMPORT tcpState, tcpServerEstablish, tcpServerAccept,
                 tcpPortNo, tcpSocketFd ;


TYPE
   nameServerState  = (unknown, us, remote) ;
   RequestType      = (getnetid, regname, lookup) ;

   CSNameServiceReq = POINTER TO RECORD
                                    CASE req: RequestType OF

                                    getnetid: |
                                    lookup  : strlen: CARDINAL |
                                    regname : netid : NetId ;
                                              strlen: CARDINAL

                                    END
                                 END ;

VAR
   nsstate    : nameServerState ;
   remoteIP   : CARDINAL ;
   thread     : DESCRIPTOR ;
   systemNetId,
   uniqueNetId: CARDINAL ;


PROCEDURE nsThread ;
VAR
   r: INTEGER ;
   v: CARDINAL ;
   fd: INTEGER ;
   s: tcpState ;
   p: DESCRIPTOR ;
BEGIN
   s := tcpServerEstablish() ;
   got to here
   v := InitInputVector(tcpSocketFd(s), MAX(PRIORITY)) ;
   LOOP
      r := printf("before WaitForIO\n");
      WaitForIO(v) ;
      fd := tcpServerAccept(s) ;
      r := printf("before InitProcess\n");
      p := InitProcess(theServer, StackSize, 'theServer') ;
      NextFd := fd ;
      r := printf("before Resume\n");
      p := Resume(p) ;
      Wait(ToBeTaken)
   END
END nsThread ;


(*
   getUniqueNetid - returns a unique netid.
*)

PROCEDURE getUniqueNetid () : NetId ;
BEGIN
   IF nsstate=us
   THEN
      INC(uniqueNetId) ;
      RETURN uniqueNetId
   ELSIF nsstate=unknown
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__,
           'csnsys has not been initialized by a call to either nameServer or resolvConf')
   ELSE
      RETURN doUniqueNetid()
   END
END getUniqueNetid ;


(*
   doUniqueNetid - construct an rpc to the name server.
*)

PROCEDURE doUniqueNetid () : NetId ;
VAR
   rq       : CSNameServiceReq ;
   new, from: NetId ;
   length   : CARDINAL ;
BEGIN
   rq.req := getnetid ;
   IF csn.Tx(hmm, NetId(2), ADR(rq), SIZE(rq.req))=csn.CsnOk
   THEN
      IF csn.Rx(hmm, from, ADR(new), SIZE(new), length)=csn.CsnOk
      THEN
         IF length#SIZE(new)
         THEN
            Halt(__FILE__, __LINE__, __FUNCTION__,
                 'rpc failed to receive unique netid, incorrect length returned')
         END ;
         RETURN new
      ELSE
         Halt(__FILE__, __LINE__, __FUNCTION__,
              'rpc failed to receive unique netid')
      END ;
   ELSE
      Halt(__FILE__, __LINE__, __FUNCTION__,
           'rpc failed to transmit get unique request to name server')
   END
END doUniqueNetid ;


(*
   nameServer - indicates that the caller is the cs name server.
*)

PROCEDURE nameServer ;
BEGIN
   IF (nsstate=unknown) OR (nsstate=us)
   THEN
      nsstate := us ;
      IF thread=NIL
      THEN
         thread := Resume(InitProcess(nsThread, 'CSN name server', StackSize))
      END
   ELSE
      Halt(__FILE__, __LINE__, __FUNCTION__,
           'name server already defined for another host')
   END
END nameServer ;


(*
   resolvConf - tells the csn subsystem to use, ip, as the
                cs name server. Not the same as a real IP name server.
*)

PROCEDURE resolvConf (ip: CARDINAL) ;
BEGIN
   IF nsstate=unknown
   THEN
      nsstate := remote ;
      remoteIP := ip
   ELSIF nsstate=remote
   THEN
      IF remoteIP#ip
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__,
              'should not be reassigning the name server ip addresses')
      END ;
      remoteIP := ip
   ELSE
      Halt(__FILE__, __LINE__, __FUNCTION__,
           'name server has already been assigned locally through a call to nameServer')
   END
END resolvConf ;


(*
   Init - 
*)

PROCEDURE Init ;
BEGIN
   uniqueNetId := 1 ;
   systemNetId := 1
END Init ;


BEGIN
   Init
END csnsys.
