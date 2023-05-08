IMPLEMENTATION MODULE csn ;


FROM SYSTEM IMPORT ADDRESS, ADR, SIZE, TurnInterrupts, ListenLoop ;
FROM COROUTINES IMPORT PROTECTION ;
FROM SysStorage IMPORT ALLOCATE, DEALLOCATE ;
FROM libc IMPORT memcpy, printf, close, write, read, readv, writev, perror, shutdown, getenv, atexit ;
FROM errno IMPORT geterrno, EAGAIN ;
FROM NumberIO IMPORT CardToStr ;
FROM StrLib IMPORT StrConCat ;
FROM M2RTS IMPORT Halt ;
FROM NameKey IMPORT Name, KeyToCharStar, makekey ;
FROM SymbolKey IMPORT NulKey, SymbolTree, PutSymKey, GetSymKey, InitTree ;
FROM Indexing IMPORT Index, InitIndex, GetIndice, PutIndice, IsIndiceInIndex ;
FROM execArgs IMPORT beginPutArg, endPutArg, getArg ;
FROM RTint IMPORT InitOutputVector, InitInputVector ;
FROM DynamicStrings IMPORT String, InitString, InitStringCharStar, KillString, Length, string ;
FROM SysTypes IMPORT IOVec ;
FROM StrLib IMPORT StrLen ;
FROM SocketControl IMPORT nonBlocking, ignoreSignals ;

FROM Executive IMPORT DESCRIPTOR, SEMAPHORE,
                      InitProcess, Resume, Wait, Signal, InitSemaphore, WaitForIO,
                      KillProcess ;

FROM sckt IMPORT tcpServerState,
                 tcpServerEstablish, tcpServerEstablishPort,
                 tcpServerAccept, getLocalIP,
                 tcpServerPortNo, tcpServerIP, tcpServerSocketFd,
                 tcpServerClientIP, tcpServerClientPortNo,
                 tcpClientState,
                 tcpClientSocket, tcpClientSocketIP, tcpClientConnect,
                 tcpClientPortNo, tcpClientIP, tcpClientSocketFd ;

FROM Lock IMPORT LOCK, GetReadAccess, ReleaseReadAccess,
                 GetWriteAccess, ReleaseWriteAccess,
                 InitLock ;


CONST
   Debugging      = TRUE ;
   CsnAssert      = 0DECAFBADH ;
   MaxDescriptors = 100 ;  (* just for testing *)
   nameServerPort = 1901 ;
   StackSize      = 10 * 1024*1024 ;

TYPE
   nameServerState  = (unknown, us, remote) ;
   requestType      = (regname, lookup) ;

   CSNameLookup = RECORD
                     req: requestType ;
                     strlen: CARDINAL
                  END ;

   CSNameReg    = RECORD
                     req   : requestType ;
                     netid : NetId ;
                     strlen: CARDINAL ;
                  END ;

   RegisteredEntry = POINTER TO RECORD
                                   netid   : NetId ;
                                   name    : Name ;
                                   known   : BOOLEAN ;
                                   waiting : SEMAPHORE ;
                                   nwaiting: CARDINAL ;
                                END ;

   (* all Queues in this module are circular lists *)
   Queue         = RECORD
                      Left,
                      Right: Desc ;
                   END ;

   (* RxInfo contains all the information necessary for a RxNb *)
   RxInfo        = RECORD
                      tpt        : Transport ;  (* which transport created this? *)
                      WhoTo,
                      WhoFrom    : NetId ;
                      Start      : ADDRESS ;
                      Length     : CARDINAL ;
                      Status     : CsnStatus ;
                      PtrToActual: POINTER TO CARDINAL ;
                   END ;

   (* RxInfo contains all the information necessary for a TxNb *)
   TxInfo        = RECORD
                      tpt    : Transport ;  (* which transport created this? *)
                      WhoTo,
                      WhoFrom: NetId ;
                      Start  : ADDRESS ;
                      Length : CARDINAL ;
                      Status : CsnStatus ;
                   END ;

   StateOfDesc   = (txinit, rxinit, txdone, rxdone) ;
   TypeOfDesc    = (rx, tx) ;

   netidThread = POINTER TO RECORD
                               tpt      : Transport ;
                               netid    : NetId ;
                               txsock   : tcpClientState ;
                               txfd,
                               rxfd     : INTEGER ;
                               rxfdtaken,
                               rxfdavail: SEMAPHORE ;
                               rxthread,
                               txthread : DESCRIPTOR ;
                               txavail  : SEMAPHORE ;
                               txpending: Desc ;
                               Left,
                               Right    : netidThread ;
                            END ;

   Transport = POINTER TO RECORD
                             sck: tcpServerState ;
                             fd : INTEGER ;    (* socket file des      *)
                             listOfActiveNetids: netidThread ;
                             rxp: DESCRIPTOR ;
                                               (* incoming server      *)
                                               (* thread for this tpt  *)
                             netid: NetId ;    (* address of transport *)
                             doneQ: Desc ;     (* holds the relevant   *)
                                               (* descriptors          *)
                             eagerReaderQ: Desc ;  (* RxNb before Test *)
                             rxavail: SEMAPHORE ;  (* eagerReaderQ     *)
                             TxQ, RxQ, TxRxQ: Barrier ;
                          END ;

   (*
      the ToDoQ is used for a Desc which has no corresponding pair.
      This will occur if a Tx occurs before a Rx or visa versa.

      the DoneQ is use for a Desc which has completed its Tx or Rx
      but which has not been released via Test.
   *)

   ProcDesc = PROCEDURE (Transport, Desc, Desc, VAR CsnStatus) : BOOLEAN ;

   Desc     = POINTER TO RECORD
                            Q          : Queue ;        (* queue of descs    *)
                            State      : StateOfDesc ;  (* current state     *)
                            InUse      : LOCK ;         (* write to free     *)
                            RxQ, TxQ,
                            TxRxQ      : Barrier ;
                            CASE Type:TypeOfDesc OF

                            rx:  rxinfo: RxInfo |
                            tx:  txinfo: TxInfo

                            END
                         END ;

   Barrier = POINTER TO RECORD
                           Next : Barrier ;
                           Sem  : SEMAPHORE ;
                           Count: CARDINAL ;
                        END ;


(*
   state transition table for Desc

   State  | Description
   =============================================================
   txinit | transmit has been initiated, descriptor contains all
          | info passed by a call to TxNb
   -------+-----------------------------------------------------
   rxinit | receive has been initiated, descriptor contains all
          | info passed by a call to RxNb
   -------+-----------------------------------------------------
   txdone | tx desc has found corresponding rx desc and tx
          | operation has been completed.
          | We now await the Test which will throw this desc away.
   -------+-----------------------------------------------------
   rxdone | rx desc has found corresponding tx desc and rx
          | operation has been completed.
          | We now await the Test which will throw this desc away.
*)


VAR
   freeDesc            : Desc ;   (* the descriptor free list      *)
   nsstate             : nameServerState ;
   nsTree              : SymbolTree ;
   nsIndex             : Index ;
   remoteName          : String ;
   thread              : DESCRIPTOR ;
   uniqueNetId         : CARDINAL ;
   nextFd              : INTEGER ;
   DescNo              : CARDINAL ;
   freeBarrier         : Barrier ;
   debugging           : BOOLEAN ;


PROCEDURE overRun ;
BEGIN
END overRun ;


(*
   InitBarrier -
*)

PROCEDURE InitBarrier () : Barrier ;
VAR
   b: Barrier ;
BEGIN
   IF freeBarrier=NIL
   THEN
      NEW(b) ;
      WITH b^ DO
         Sem := InitSemaphore(0, 'Barrier') ;
         Count := 0 ;
         Next := NIL
      END
   ELSE
      b := freeBarrier ;
      freeBarrier := freeBarrier^.Next
   END ;
   RETURN( b )
END InitBarrier ;


(*
   KillBarrier -
*)

PROCEDURE KillBarrier (b: Barrier) : Barrier ;
BEGIN
   b^.Next := freeBarrier ;
   freeBarrier := b ;
   RETURN( NIL )
END KillBarrier ;


(*
   block -
*)

PROCEDURE block (b: Barrier) ;
BEGIN
   WITH b^ DO
      INC(Count) ;
      Wait(Sem)
   END
END block ;


(*
   release -
*)

PROCEDURE release (b: Barrier) ;
BEGIN
   WITH b^ DO
      WHILE Count>0 DO
         Signal(Sem) ;
         DEC(Count)
      END ;
   END
END release ;


PROCEDURE localWrite (fd: INTEGER; ch: CHAR) ;
VAR
   r: INTEGER ;
BEGIN
   r := write(fd, ADR(ch), SIZE(ch)) ;
   IF r=-1
   THEN
      printf("client has gone away - need to KillProcess\n");
      KillProcess
   END
END localWrite ;


PROCEDURE localWriteS (fd: INTEGER; s: ARRAY OF CHAR) ;
VAR
   r: INTEGER ;
BEGIN
   r := write(fd, ADR(s), StrLen(s)) ;
   IF r=-1
   THEN
      printf("WriteS client has gone away - need to KillProcess\n");
      KillProcess
   END
END localWriteS ;


PROCEDURE localRead (fd: INTEGER) : CHAR ;
VAR
   r : INTEGER ;
   ch: CHAR ;
BEGIN
   r := read(fd, ADR(ch), SIZE(ch)) ;
   IF r=-1
   THEN
      printf("client has gone away - need to KillProcess\n");
      KillProcess
   END ;
   RETURN ch
END localRead ;


(*
   doReadN - waits for vector, v, to become ready and then attempts to read.
*)

PROCEDURE doReadN (v: CARDINAL; fd: INTEGER; a: ADDRESS; n: CARDINAL) : INTEGER ;
VAR
   r,
   c, i: INTEGER ;
BEGIN
   IF Debugging AND debugging
   THEN
      printf('in doReadN (fd = %d) want to read %d bytes\n', fd, n)
   END ;
   c := 0 ;
   WHILE n>0 DO
      IF n>VAL(CARDINAL, MAX(INTEGER))
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__, 'n is too large') ;
      END ;
      REPEAT
         WaitForIO(v) ;
         i := read(fd, a, n)
      UNTIL (i>=0) OR (geterrno() # EAGAIN) ;
      IF i<0
      THEN
         perror("read") ;
         Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doReadN') ;
         RETURN( i )
      END ;
      (* printf('doReadN (fd = %d) has read %d bytes  (n is %d bytes)\n', fd, i, n) ; *)
      IF Debugging AND debugging
      THEN
         printf('doReadN (fd = %d) has read %d bytes\n', fd, i) ;
         IF VAL(INTEGER, n)>i
         THEN
            printf('doReadN (fd = %d) ****needs**** to read more\n', fd)
         END
      END ;
      INC(a, i) ;
      IF i>INTEGER(n)
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__, 'n will underflow..') ;
      END ;
      (* printf('doReadN before DEC (n = %d) (i is %d)\n', n, i) ; *)
      DEC(n, i) ;
      (* printf('doReadN after  DEC (n = %d) (i is %d)\n', n, i) ; *)
      INC(c, i)
   END ;
   IF Debugging AND debugging
   THEN
      printf('doReadN (fd = %d) finished, total read %d bytes\n', fd, c)
   END ;
   RETURN( c )
END doReadN ;


(*
   doWriteN - waits for vector, v, to become ready and then attempts to write.
*)

PROCEDURE doWriteN (v: CARDINAL; fd: INTEGER; a: ADDRESS; n: CARDINAL) : INTEGER ;
VAR
   r,
   c, i: INTEGER ;
BEGIN
   IF Debugging AND debugging
   THEN
      printf('in doWriteN want to write %d bytes\n', n)
   END ;
   c := 0 ;
   WHILE n>0 DO
      IF n>VAL(CARDINAL, MAX(INTEGER))
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__, 'n is too large') ;
      END ;
      REPEAT
         WaitForIO(v) ;
         i := write(fd, a, n) ;
      UNTIL (i>=0) OR (geterrno() # EAGAIN) ;
      IF i<0
      THEN
         perror("write") ;
         Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doWriteN') ;
         RETURN( i )
      END ;
      IF Debugging AND debugging
      THEN
         printf('doWriteN (fd = %d) has written %d bytes\n', fd, i) ;
         IF VAL(INTEGER, n)>i
         THEN
            printf('doWriteN (fd = %d) ****needs**** to write more\n', fd)
         END
      END ;
      INC(a, i) ;
      IF i>INTEGER(n)
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__, 'n will underflow..') ;
      END ;
      (* printf('doWriteN before DEC (n = %d) (i is %d)\n', n, i) ; *)
      DEC(n, i) ;
      (* printf('doWriteN after  DEC (n = %d) (i is %d)\n', n, i) ; *)
      INC(c, i)
   END ;
   IF Debugging AND debugging
   THEN
      printf('doWriteN (fd = %d) finished, total write %d bytes\n', fd, c)
   END ;
   RETURN( c )
END doWriteN ;


(*
   doReadV - waits for vector, v, to become ready and then attempts to read.
*)

PROCEDURE doReadV (v: CARDINAL; fd: INTEGER; iov: ADDRESS; n: CARDINAL) : INTEGER ;
BEGIN
   WaitForIO(v) ;
   RETURN( readv(fd, iov, n) )
END doReadV ;


(*
   doWriteV - waits for vector, v, to become ready and then attempts to write.
*)

PROCEDURE doWriteV (v: CARDINAL; fd: INTEGER; iov: ADDRESS; n: CARDINAL) : INTEGER ;
BEGIN
   WaitForIO(v) ;
   RETURN( writev(fd, iov, n) )
END doWriteV ;


(*
   doAccept -
*)

PROCEDURE doAccept (v: CARDINAL; t: tcpServerState) : INTEGER ;
VAR
   fd, r: INTEGER ;
BEGIN
   REPEAT
      WaitForIO(v) ;
      fd := tcpServerAccept(t) ;
   UNTIL (fd >= 0) OR (geterrno() # EAGAIN) ;
   r := nonBlocking(fd) ;
   RETURN( fd )
END doAccept ;


PROCEDURE handleRequest ;
VAR
   fd: INTEGER ;
   vr,
   vw: CARDINAL ;
   ch: CHAR ;
   r : INTEGER ;
   req: requestType ;
   s : ADDRESS ;
   l : CARDINAL ;
   n : NetId ;
   c : CARDINAL ;
BEGIN
   getArg(fd) ;

   r := nonBlocking(fd) ;
   vr := InitInputVector(fd, MAX(PROTECTION)) ;
   vw := InitOutputVector(fd, MAX(PROTECTION)) ;
   IF Debugging AND debugging
   THEN
      printf("inside `handleRequest' using fd=%d\n", fd)
   END ;
   r := doReadN(vr, fd, ADR(req), SIZE(req)) ;
   IF Debugging AND debugging
   THEN
      printf("inside `handleRequest' read request fd=%d\n", fd)
   END ;
   CASE req OF

   lookup:  IF Debugging AND debugging
            THEN
               printf("inside `handleRequest' read seen lookup fd=%d\n", fd)
            END ;
            r := doReadN(vr, fd, ADR(l), SIZE(l)) ;
            IF Debugging AND debugging
            THEN
               printf("inside `handleRequest' lookup string length fd=%d\n",
                      l, fd)
            END ;
            ALLOCATE(s, l) ;
            IF s=NIL
            THEN
               Halt(__FILE__, __LINE__, __FUNCTION__, "out of memory")
            END ;
            r := doReadN(vr, fd, s, l) ;
            IF r<0
            THEN
               Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doReadN')
            END ;
            IF Debugging AND debugging
            THEN
               printf("lookup name request for %s\n", s)
            END ;
            n := doLookup(makekey(s)) ;
            IF Debugging AND debugging
            THEN
               printf('lookup name before doWrite, sending %x:%d\n',
                      n.ip, n.port)
            END ;
            r := doWriteN(vw, fd, ADR(n), SIZE(n)) ;
            IF r<0
            THEN
               Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doWriteN')
            END ;
            IF Debugging AND debugging
            THEN
               printf("lookup name responded\n")
            END ;
            DEALLOCATE(s, l) |

   regname: IF Debugging AND debugging
            THEN
               printf("inside `handleRequest' regname (reading netid) fd=%d\n",
                           fd)
            END ;
            r := doReadN(vr, fd, ADR(n), SIZE(n)) ;
            IF r<0
            THEN
               Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doReadN')
            END ;
            IF Debugging AND debugging
            THEN
               printf("inside `handleRequest' regname  netid.ip = %x:%d  (reading length) fd=%d\n",
                      n.ip, n.port, fd)
            END ;
            r := doReadN(vr, fd, ADR(l), SIZE(l)) ;
            IF r<0
            THEN
               Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doReadN')
            END ;
            IF Debugging AND debugging
            THEN
               printf("inside `handleRequest' regname string length = %d fd=%d\n",
                           l, fd)
            END ;
            ALLOCATE(s, l) ;
            IF s=NIL
            THEN
               Halt(__FILE__, __LINE__, __FUNCTION__, "out of memory")
            END ;
            IF Debugging AND debugging
            THEN
               printf("register name (reading string contents)  fd = %d\n", fd)
            END ;
            r := doReadN(vr, fd, s, l) ;
            IF r<0
            THEN
               Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doReadN')
            END ;
            IF Debugging AND debugging
            THEN
               printf("register name request for %s  (calling doRegister)\n", s)
            END ;
            doRegister(n, makekey(s)) ;
            IF Debugging AND debugging
            THEN
               printf("doRegister finished\n")
            END ;
            DEALLOCATE(s, l) ;
            c := CsnAssert ;
            r := doWriteN(vw, fd, ADR(c), SIZE(c)) ;
            IF r<0
            THEN
               Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doWriteN')
            END

   ELSE
      Halt(__FILE__, __LINE__, __FUNCTION__, 'not expecting this request')
   END ;
   IF Debugging AND debugging
   THEN
      printf("handleRequest, shutdown(fd = %d)\n", fd)
   END ;
   r := shutdown(fd, 2) ;
   IF r<0
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad shutdown')
   END ;
   IF Debugging AND debugging
   THEN
      printf("handleRequest, close(fd = %d)\n", fd)
   END ;
   r := close(fd) ;
   IF r<0
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad close')
   END ;
   KillProcess
END handleRequest ;


PROCEDURE nsThread ;
VAR
   r  : INTEGER ;
   v  : CARDINAL ;
   sfd,
   fd : INTEGER ;
   s  : tcpServerState ;
   p  : DESCRIPTOR ;
BEGIN
   s := tcpServerEstablishPort(nameServerPort) ;
   IF tcpServerPortNo(s)#nameServerPort
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__,
           'name server needs to run on specific port and it is already in use')
   END ;
   sfd := tcpServerSocketFd(s) ;
   r := nonBlocking(sfd) ;
   v := InitInputVector(sfd, MAX(PROTECTION)) ;
   LOOP
      IF Debugging AND debugging
      THEN
         printf("nameserver is before WaitForIO (for connection on port %d)\n",
                tcpServerPortNo(s))
      END ;
      fd := doAccept(v, s) ;
      IF Debugging AND debugging
      THEN
         printf("before InitProcess handleRequest (fd = %d)\n", fd)
      END ;
      beginPutArg(fd) ;
      p := Resume(InitProcess(handleRequest, StackSize, 'handleRequest')) ;
      endPutArg
   END
END nsThread ;


(*
   nameServer - indicates that the caller is the cs name server.
*)

PROCEDURE nameServer ;
BEGIN
   IF nsstate=unknown
   THEN
      remoteName := InitString('localhost') ;
      nsstate := us ;
      IF thread=NIL
      THEN
         InitTree(nsTree) ;
         uniqueNetId := 0 ;
         nsIndex := InitIndex(1) ;
         thread := Resume(InitProcess(nsThread, StackSize, 'CSN name server'))
      END
   ELSE
      Halt(__FILE__, __LINE__, __FUNCTION__,
           'name server already defined for another host')
   END
END nameServer ;


(*
   resolvConf - tells the csn subsystem to use, name, as the
                cs name server. Not the same as a real IP name server.
*)

PROCEDURE resolvConf (name: ADDRESS) ;
BEGIN
   IF nsstate=us
   THEN
      remoteName := InitStringCharStar(name)
   ELSIF nsstate=unknown
   THEN
      nsstate := remote ;
      remoteName := InitStringCharStar(name)
   ELSIF nsstate=remote
   THEN
      IF remoteName#NIL
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__,
              'should not be reassigning the name server')
      END ;
      remoteName := InitStringCharStar(name)
   ELSE
      Halt(__FILE__, __LINE__, __FUNCTION__,
           'name server is in an unknown state')
   END
END resolvConf ;


(*
   doLookup - returns a NetId corresponding to a name, s.
*)

PROCEDURE doLookup (s: Name) : NetId ;
VAR
   e: RegisteredEntry ;
   i: CARDINAL ;
   a: String ;
   r: INTEGER ;
BEGIN
   i := GetSymKey(nsTree, s) ;
   IF i=NulKey
   THEN
      INC(uniqueNetId) ;
      NEW(e) ;
      WITH e^ DO
         name := s ;
         netid := NullNetId ;
         known := FALSE ;
         waiting := InitSemaphore(0, 'ns waiting') ;
         nwaiting := 0
      END ;
      PutIndice(nsIndex, uniqueNetId, e) ;
      PutSymKey(nsTree, s, uniqueNetId)
   ELSE
      e := GetIndice(nsIndex, i)
   END ;
   WITH e^ DO
      IF NOT known
      THEN
         IF Debugging AND debugging
         THEN
            a := InitStringCharStar(KeyToCharStar(s)) ;
            printf('about to block when looking up transport %s (currently %d threads waiting for it)\n',
                   a, nwaiting) ;
            a := KillString(a)
         END ;
         INC(nwaiting) ;
         Wait(waiting)
      END ;
      IF Debugging AND debugging
      THEN
         a := InitStringCharStar(KeyToCharStar(s)) ;
         printf('woken up, transport %s is known (%x:%d\n',
                     a, netid.ip, netid.port) ;
         a := KillString(a)
      END ;
      RETURN netid
   END
END doLookup ;


(*
   doRegister - registers netid, n, with name, s.
*)

PROCEDURE doRegister (n: NetId; s: Name) ;
VAR
   e: RegisteredEntry ;
   i: CARDINAL ;
   r: INTEGER ;
   a: String ;
BEGIN
   i := GetSymKey(nsTree, s) ;
   IF i=NulKey
   THEN
      IF Debugging AND debugging
      THEN
         a := InitStringCharStar(KeyToCharStar(s)) ;
         printf('about to register transport %s (nobody waiting is for it)\n', a) ;
         a := KillString(a)
      END ;
      INC(uniqueNetId) ;
      NEW(e) ;
      WITH e^ DO
         netid := n ;
         name := s ;
         known := TRUE ;
         waiting := InitSemaphore(0, 'ns waiting') ;
         nwaiting := 0
      END ;
      PutIndice(nsIndex, uniqueNetId, e) ;
      PutSymKey(nsTree, s, uniqueNetId)
   ELSE
      e := GetIndice(nsIndex, i) ;
      WITH e^ DO
         IF known
         THEN
            a := InitStringCharStar(KeyToCharStar(s)) ;
            printf('transport %s has already been registered\n', a) ;
            IF (netid.ip=n.ip) AND (netid.port=n.port)
            THEN
               printf('transport has same netid as before (ignoring)\n')
            ELSE
               Halt(__FILE__, __LINE__, __FUNCTION__,
                    'transport is being registered with a different netid')
            END ;
            a := KillString(a)
         ELSE
            IF Debugging AND debugging
            THEN
               a := InitStringCharStar(KeyToCharStar(s)) ;
               printf('about to register transport %s (%d threads waiting for it)\n',
                           a, n) ;
               a := KillString(a)
            END ;
            known := TRUE ;
            netid := n ;
            WHILE nwaiting>0 DO
               Signal(waiting) ;
               DEC(nwaiting)
            END
         END
      END
   END
END doRegister ;


(*
   serverThread -
*)

PROCEDURE serverThread ;
VAR
   t      : Transport ;
   th     : netidThread ;
   r, f, v: INTEGER ;
   d      : Desc ;
BEGIN
   getArg(t) ;
   WITH t^ DO
      r := nonBlocking(fd) ;
      v := InitInputVector(fd, MAX(PROTECTION)) ;
      LOOP
         printf("vector including fd = %d\n", fd) ;
         f := doAccept(v, sck) ;
         netid.ip := tcpServerClientIP(sck) ;
         netid.port := tcpServerClientPortNo(sck) ;
         IF Debugging AND debugging
         THEN
            printf("serverThread accepted connection from %x:%d\n", netid.ip, netid.port)
         END ;
         th := findThread(t, netid, rx) ;
         WITH th^ DO
            rxfd := f ;
            Signal(rxfdavail) ;
            Wait(rxfdtaken)
         END
      END
   END
END serverThread ;


(*
   Open - creates a new transport, t, and returns status.
*)

PROCEDURE Open (VAR t: Transport) : CsnStatus ;
VAR
   Status: CsnStatus ;
   r     : INTEGER ;
BEGIN
   NEW(t) ;
   IF t=NIL
   THEN
      Status := CsnNoHeap
   ELSE
      WITH t^ DO
         TxQ := InitBarrier() ;
         RxQ := InitBarrier() ;
         TxRxQ := InitBarrier() ;
         rxavail := InitSemaphore(0, 'rxavail') ;
         eagerReaderQ := NIL ;
         sck := tcpServerEstablish() ;     (* start listening on a tcp port no *)
         listOfActiveNetids := NIL ;
         netid.ip := getLocalIP(sck) ;
         netid.port := tcpServerPortNo(sck) ;
         fd := tcpServerSocketFd(sck) ;
         doneQ := NIL ;
         beginPutArg(t) ;
         rxp := Resume(InitProcess(serverThread, StackSize, 'serverThread')) ;
         endPutArg
      END ;
      Status := CsnOk
   END ;
   RETURN( Status )
END Open ;


(*
   GetRemote - returns the remote NetId of, d.
*)

PROCEDURE GetRemote (d: Desc) : NetId ;
BEGIN
   IF d^.Type=rx
   THEN
      RETURN( d^.rxinfo.WhoFrom )
   ELSE
      RETURN( d^.txinfo.WhoTo )
   END
END GetRemote ;


(*
   descMatch - returns TRUE if the netid, n1, matches the remote communication
               as specified by, n2.
*)

PROCEDURE descMatch (n1, n2: NetId) : BOOLEAN ;
BEGIN
   RETURN( (n1.ip=n2.ip) AND (n1.port=n2.port) )
END descMatch ;


(*
   txWorker -
*)

PROCEDURE txWorker ;
VAR
   th: netidThread ;
   nBytes,
   v1, v2 : CARDINAL ;
   d      : Desc ;
BEGIN
   getArg(th) ;
   WITH th^ DO
      txsock := tcpClientSocketIP(netid.ip, netid.port) ;
      v1 := InitInputVector(tcpClientSocketFd(txsock), MAX(PROTECTION)) ;
      IF Debugging AND debugging
      THEN
         printf("txWorker before WaitForIO\n")
      END ;
      WaitForIO(v1) ;
      IF Debugging AND debugging
      THEN
         printf("txWorker after WaitForIO\n")
      END ;
      txfd := tcpClientConnect(txsock) ;
      v2 := InitOutputVector(txfd, MAX(PROTECTION)) ;
      LOOP
         IF Debugging AND debugging
         THEN
            printf("txWorker before wait txavail\n")
         END ;
         Wait(txavail) ;
         d := txpending ;
         SubFrom(txpending, d) ;
         WITH d^.txinfo DO
            nBytes := Length ;
            IF Debugging AND debugging
            THEN
               printf("txWorker before write nBytes=%d\n", nBytes)
            END ;
            IF doWriteN(v2, txfd, ADR(nBytes), SIZE(nBytes)) = SIZE(nBytes)
            THEN
               IF Debugging AND debugging
               THEN
                  printf("txWorker before write of data\n")
               END ;
               IF doWriteN(v2, txfd, Start, Length)=Length
               THEN
                  Status := CsnOk
               ELSE
                  Status := CsnOverrun ;
                  printf('txWorker warning csnoverrun  %x:%d\n',
                         netid.ip, netid.port) ;
                  overRun
               END
            ELSE
               Status := CsnOverrun ;
               printf('txWorker warning csnoverrun  %x:%d\n',
                      netid.ip, netid.port) ;
               overRun
            END ;
            IF Debugging AND debugging
            THEN
               printf("txWorker adding to doneQ\n")
            END ;
            AddTo(tpt^.doneQ, d) ;
            release(tpt^.TxQ) ;
            release(tpt^.TxRxQ)
         END
      END
   END
END txWorker ;


(*
   rxWorker -
*)

PROCEDURE rxWorker ;
VAR
   th     : netidThread ;
   nBytes : CARDINAL ;
   v      : CARDINAL ;
   localfd,
   i, r   : INTEGER ;
   d      : Desc ;
   a      : ADDRESS ;
BEGIN
   getArg(th) ;
   WITH th^ DO
      IF Debugging AND debugging
      THEN
         printf('rxWorker before rxfdavail in netidThread %x:%d\n',
                     netid.ip, netid.port)
      END ;
      Wait(rxfdavail) ;
      localfd := rxfd ;
      Signal(rxfdtaken) ;
      r := nonBlocking(localfd) ;
      v := InitInputVector(localfd, MAX(PROTECTION)) ;
      LOOP
         IF Debugging AND debugging
         THEN
            printf('rxWorker before WaitForIO in netidThread %x:%d\n',
                        netid.ip, netid.port)
         END ;
         r := nonBlocking(localfd) ;
         WaitForIO(v) ;
         IF Debugging AND debugging
         THEN
            printf('rxWorker before rxavail in netidThread %x:%d\n',
                   netid.ip, netid.port)
         END ;
         Wait(tpt^.rxavail) ;
         d := tpt^.eagerReaderQ ;
         SubFrom(tpt^.eagerReaderQ, d) ;
         WITH d^.rxinfo DO
            r := nonBlocking(localfd) ;
            i := doReadN(v, localfd, ADR(nBytes), SIZE(nBytes)) ;
            IF i<0
            THEN
               perror('rxWorker') ;
               printf('rxWorker warning csnoverrun  %x:%d\n',
                      netid.ip, netid.port) ;
               Status := CsnOverrun ;
               overRun ;
               Halt(__FILE__, __LINE__, __FUNCTION__, 'bad rxWorker')
            ELSE
               IF Debugging AND debugging
               THEN
                  printf("rxWorker before doReadN (Length=%d) (nBytes=%d)\n",
                         Length, nBytes)
               END ;
               IF Length<nBytes
               THEN
                  printf('rxWorker warning csnoverrun  %x:%d\n',
                         netid.ip, netid.port) ;
                  overRun ;
                  Status := CsnOverrun ;
                  i := doReadN(v, localfd, Start, Length) ;
                  DEC(nBytes, Length) ;
                  ALLOCATE(a, nBytes) ;
                  i := doReadN(v, localfd, a, nBytes) ;
                  DEALLOCATE(a, nBytes) ;
                  nBytes := Length
               ELSE
                  i := doReadN(v, localfd, Start, nBytes) ;
                  IF Debugging AND debugging
                  THEN
                     printf("rxWorker doReadN returns %d\n", i)
                  END ;
                  IF i>=0
                  THEN
                     Status := CsnOk
                  ELSE
                     printf('rxWorker warning csnoverrun  %x:%d\n',
                            netid.ip, netid.port) ;
                     overRun ;
                     Status := CsnOverrun
                  END ;
               END ;
               IF Debugging AND debugging
               THEN
                  printf("rxWorker before add to doneQ\n")
               END
            END ;
            WhoFrom := netid ;
            PtrToActual^ := nBytes ;
            AddTo(tpt^.doneQ, d) ;
            release(tpt^.RxQ) ;
            release(tpt^.TxRxQ)
         END
      END
   END
END rxWorker ;


(*
   newThreads - creates two new threads to handle the communication
                as defined by, d.
*)

PROCEDURE newThreads (t: Transport; nid: NetId; k: TypeOfDesc) : netidThread ;
VAR
   th: netidThread ;
BEGIN
   NEW(th) ;
   IF th=NIL
   THEN
      RETURN( NIL )
   END ;
   WITH th^ DO
      tpt := t ;
      netid := nid ;
      rxfdavail := InitSemaphore(0, 'rxfdavail') ;
      rxfdtaken := InitSemaphore(0, 'rxfdtaken') ;
      txavail := InitSemaphore(0, 'txavail') ;
      txpending := NIL ;
      Left := NIL ;
      Right := NIL ;
      IF k=tx
      THEN
         beginPutArg(th) ;
         txthread := Resume(InitProcess(txWorker, StackSize, 'txWorker')) ;
         endPutArg
      ELSE
         beginPutArg(th) ;
         rxthread := Resume(InitProcess(rxWorker, StackSize, 'rxWorker')) ;
         endPutArg
      END
   END ;
   RETURN( th )
END newThreads ;


(*
   findThreadNetid - returns a netidThread which will serve NetId, nid.
*)

PROCEDURE findThreadNetid (t: Transport; nid: NetId) : netidThread ;
VAR
   n: netidThread ;
BEGIN
   WITH t^ DO
      n := listOfActiveNetids ;
      IF n#NIL
      THEN
         REPEAT
            IF descMatch(nid, n^.netid)
            THEN
               RETURN( n )
            END ;
            n := n^.Right
         UNTIL n=listOfActiveNetids
      END
   END ;
   RETURN( NIL )
END findThreadNetid ;


(*
   findThread - returns a netidThread which will serve NetId, nid.
                If a thread is not found, then a new one is created
                and returned.
*)

PROCEDURE findThread (t: Transport; nid: NetId; k: TypeOfDesc) : netidThread ;
VAR
   f: netidThread ;
BEGIN
   f := findThreadNetid(t, nid) ;
   IF f=NIL
   THEN
      f := newThreads(t, nid, k) ;
      IF f=NIL
      THEN
         RETURN( NIL )
      END ;
      addThreadTo(t^.listOfActiveNetids, f)
   ELSE
      WITH f^ DO
         IF txthread=NIL
         THEN
            beginPutArg(f) ;
            txthread := Resume(InitProcess(txWorker, StackSize, 'txWorker')) ;
            endPutArg
         END
      END
   END ;
   RETURN( f )
END findThread ;


(*
   decodeDesc - decodes the descriptor.
*)

PROCEDURE decodeTxDesc (t: Transport; d: Desc) : CsnStatus ;
VAR
   th: netidThread ;
BEGIN
   WITH t^ DO
      th := findThread(t, GetRemote(d), tx) ;
      IF th=NIL
      THEN
         RETURN( CsnNoHeap )
      END ;
      WITH th^ DO
         IF Debugging AND debugging
         THEN
            printf('adding desc to txpending and Signal txavail netidThread %x:%d\n',
                   netid.ip, netid.port)
         END ;
         AddTo(txpending, d) ;
         Signal(txavail)
      END
   END ;
   RETURN( CsnOk )
END decodeTxDesc ;


(*
   decodeRxDesc - decodes the descriptor.
*)

PROCEDURE decodeRxDesc (t: Transport; d: Desc) : CsnStatus ;
VAR
   th: netidThread ;
   r : INTEGER ;
BEGIN
   WITH t^ DO
      IF Debugging AND debugging
      THEN
         printf('adding desc to eagerReaderQ netidThread %x:%d\n',
                     netid.ip, netid.port)
      END ;
      AddTo(eagerReaderQ, d) ;
      Signal(rxavail)
   END ;
   RETURN( CsnOk )
END decodeRxDesc ;


(*
   Close - closes a transport, t, and returns status.
*)

PROCEDURE Close (VAR t: Transport) : CsnStatus ;
VAR
   r: INTEGER ;
   n: netidThread ;
BEGIN
   WITH t^ DO
      IF (doneQ#NIL) OR (eagerReaderQ#NIL)
      THEN
         RETURN( CsnBusy )
      END ;
      n := listOfActiveNetids ;
      IF n#NIL
      THEN
         REPEAT
            IF n^.txpending#NIL
            THEN
               RETURN( CsnBusy )
            END ;
            r := close(n^.txfd) ;
            r := close(n^.rxfd) ;
            n := n^.Right
         UNTIL n=listOfActiveNetids
      END ;
      r := close(fd)
   END ;
   RETURN( CsnOk )
END Close ;


(*
   addThreadTo - adds thread, n, to, Head.
*)

PROCEDURE addThreadTo (VAR Head: netidThread; n: netidThread) ;
BEGIN
   IF Head=NIL
   THEN
      Head := n ;
      n^.Left := n ;
      n^.Right := n
   ELSE
      n^.Right := Head ;
      n^.Left := Head^.Left ;
      Head^.Left^.Right := n ;
      Head^.Left := n
   END
END addThreadTo ;


(*
   AddTo - adds descriptor, d, to a specified queue.
*)

PROCEDURE AddTo (VAR Head: Desc; d: Desc) ;
BEGIN
   IF Head=NIL
   THEN
      Head := d ;
      d^.Q.Left := d ;
      d^.Q.Right := d
   ELSE
      d^.Q.Right := Head ;
      d^.Q.Left := Head^.Q.Left ;
      Head^.Q.Left^.Q.Right := d ;
      Head^.Q.Left := d
   END
END AddTo ;


(*
   SubFrom - removes a descriptor, d, from a queue.
*)

PROCEDURE SubFrom (VAR Head: Desc; d: Desc) ;
BEGIN
   IF (d^.Q.Left=Head) AND (d=Head)
   THEN
      Head := NIL
   ELSE
      IF Head=d
      THEN
         Head := Head^.Q.Right
      END ;
      d^.Q.Left^.Q.Right := d^.Q.Right ;
      d^.Q.Right^.Q.Left := d^.Q.Left
   END
END SubFrom ;


(*
   NewDesc - allocates a new descriptor.
*)

PROCEDURE NewDesc () : Desc ;
VAR
   d: Desc ;
BEGIN
   INC(DescNo) ;
   IF DescNo=MaxDescriptors
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'too many descriptors have been allocated')
   END ;
   IF freeDesc=NIL
   THEN
      NEW(d) ;
      d^.InUse := InitLock('Desc')
   ELSE
      d := freeDesc ;
      freeDesc := freeDesc^.Q.Right ;
      ReleaseWriteAccess(d^.InUse)
   END ;
   RETURN( d )
END NewDesc ;


(*
   DisposeDesc - deallocates an old Desc.
*)

PROCEDURE DisposeDesc (d: Desc) : Desc ;
BEGIN
   GetWriteAccess(d^.InUse) ;
   IF DescNo=0
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'too many Descriptors have been disposed')
   END ;
   DEC(DescNo) ;
   d^.Q.Right := freeDesc ;
   freeDesc := d ;
   RETURN( NIL )
END DisposeDesc ;


(*
   buildLookupReq - builds a lookup request rpc and sends it to the
                    name server.
*)

PROCEDURE buildLookupReq (name: ARRAY OF CHAR) : NetId ;
VAR
   cs      : CSNameLookup ;
   s       : String ;
   iov     : ARRAY [0..1] OF IOVec ;
   sk      : tcpClientState ;
   vr, vw,
   r, fd   : INTEGER ;
   n       : NetId ;
   ch      : CHAR ;
BEGIN
   sk := tcpClientSocket(string(remoteName), nameServerPort) ;
   fd := tcpClientConnect(sk) ;
   WITH cs DO
      req := lookup ;
      strlen := StrLen(name)+1 ;  (* we send the nul *)
   END ;
   s := InitString(name) ;
   vr := InitInputVector(fd, MAX(PROTECTION)) ;
   vw := InitOutputVector(fd, MAX(PROTECTION)) ;

   r := doWriteN(vw, fd, ADR(cs), SIZE(cs)) ;
   IF r<0
   THEN
      perror('doWriteN') ;
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doWriteN')
   END ;
   r := doWriteN(vw, fd, string(s), Length(s)+1) ;
   IF r<0
   THEN
      perror('doWriteN') ;
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doWriteN')
   END ;
   r := doReadN(vr, fd, ADR(n), SIZE(n)) ;
   IF r<0
   THEN
      perror('readv') ;
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad read')
   END ;
   IF Debugging AND debugging
   THEN
      printf("buildLookupReq for %s has found %x:%d\n", string(s), n.ip, n.port) ;
   END ;
   IF Debugging AND debugging
   THEN
      printf("buildLookupReq, close(fd = %d)\n", fd)
   END ;
   r := shutdown(fd, 2) ;
   IF r<0
   THEN
      perror('shutdown') ;
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad shutdown')
   END ;

   IF Debugging AND debugging
   THEN
      printf("buildLookupReq, close(fd = %d)\n", fd)
   END ;
   r := close(fd) ;
   IF r<0
   THEN
      perror('close') ;
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad close')
   END ;
   s := KillString(s) ;
   RETURN( n )
END buildLookupReq ;


(*
   buildRegisterReq - builds and sends an rpc to the name server
*)

PROCEDURE buildRegisterReq (n: NetId; name: ARRAY OF CHAR) ;
VAR
   cs      : CSNameReg ;
   s       : String ;
   sk      : tcpClientState ;
   vr, vw,
   r, fd   : INTEGER ;
   c       : CARDINAL ;
BEGIN
   sk := tcpClientSocket(remoteName, nameServerPort) ;
   fd := tcpClientConnect(sk) ;
   WITH cs DO
      req := regname ;
      netid := n ;
      strlen := StrLen(name)+1  (* we send the nul *)
   END ;
   s := InitString(name) ;
   vw := InitOutputVector(fd, MAX(PROTECTION)) ;
   vr := InitInputVector(fd, MAX(PROTECTION)) ;
   r := doWriteN(vw, fd, ADR(cs), SIZE(cs)) ;
   IF r<0
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doWriteN')
   END ;
   (* send the nul as well *)
   r := doWriteN(vw, fd, string(s), Length(s)+1) ;
   IF r<0
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad doWriteN')
   END ;
   IF Debugging AND debugging
   THEN
      printf("buildRegister for %s is %x:%d\n", string(s), n.ip, n.port)
   END ;
   r := doReadN(vr, fd, ADR(c), SIZE(c)) ;
   IF c#CsnAssert
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'CsnAssert failed')
   END ;
   IF r<0
   THEN
      perror('read') ;
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad read')
   END ;
   IF Debugging AND debugging
   THEN
      printf("buildRegisterReq, shutdown(fd = %d)\n", fd)
   END ;
   r := shutdown(fd, 2) ;
   IF r<0
   THEN
      perror('shutdown') ;
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad shutdown')
   END ;
   IF Debugging AND debugging
   THEN
      printf("buildRegisterReq, close(fd = %d)\n", fd)
   END ;
   r := close(fd) ;
   IF r<0
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'bad close')
   END ;
   s := KillString(s)
END buildRegisterReq ;


(*
   RegisterName - gives a, name, to transport, t, which can later be
                  looked up by another process.
*)

PROCEDURE RegisterName (t: Transport; name: ARRAY OF CHAR) : CsnStatus ;
VAR
   Status: CsnStatus ;
   index : CARDINAL ;
   s     : String ;
BEGIN
   IF Debugging AND debugging
   THEN
      s := InitString(name) ;
      printf("RegisterName (%s)\n", string(s))
   END ;
   IF (nsstate=us) OR (nsstate=remote)
   THEN
      buildRegisterReq(t^.netid, name)
   ELSE
      Halt(__FILE__, __LINE__, __FUNCTION__,
           'configuration error, name service has not been specified')
   END ;
   IF Debugging AND debugging
   THEN
      printf("RegisterName finishing (%s)\n", s) ;
      s := KillString(s)
   END ;
   RETURN( CsnOk )
END RegisterName ;


(*
   LookupName - blocks until a transport, t, becomes registered with, name.
*)

PROCEDURE LookupName (VAR n: NetId; name: ARRAY OF CHAR) : CsnStatus ;
VAR
   Status: CsnStatus ;
   index : CARDINAL ;
   s     : String ;
BEGIN
   IF Debugging AND debugging
   THEN
      s := InitString(name) ;
      printf("LookupName (%s)\n", string(s))
   END ;
   IF (nsstate=us) OR (nsstate=remote)
   THEN
      n := buildLookupReq(name) ;
      Status := CsnOk
   ELSE
      Status := CsnIllegalNetId ;
      Halt(__FILE__, __LINE__, __FUNCTION__,
           'configuration error, name service has not been specified')
   END ;
   IF Debugging AND debugging
   THEN
      printf("LookupName finishing (%s)\n", s) ;
      s := KillString(s)
   END ;
   RETURN( Status )
END LookupName ;


(*
   Tx - transmits a block of memory to a network address, n.
        The block of memory is defined as: a..a+l.
*)

PROCEDURE Tx (t: Transport; n: NetId; a: ADDRESS; l: CARDINAL) : CsnStatus ;
VAR
   status: CsnStatus ;
BEGIN
   (* no need for disabling interrupts in this procedure *)
   status := TxNb(t, n, a, l) ;
   IF status=CsnOk
   THEN
      n := NullNetId ;
      status := Test(t, CsnFlags{CsnTxReady}, MAX(CARDINAL), n, a, status) ;
      IF status=CsnTxReady
      THEN
         RETURN( CsnOk )
      END
   END ;
   RETURN( status )
END Tx ;


(*
   Rx - receives a message into a block of memory from a network address, n.
        Note that the actual number of bytes received can be smaller than
        the block of memory defined in the call to Rx.
        If the network address is NullId then it will accept a message from
        any other transport. When the function returns NetId will contain
        the netid of the sender.
*)

PROCEDURE Rx (t: Transport; VAR n: NetId; a: ADDRESS; l: CARDINAL;
              VAR ActualReceived: CARDINAL) : CsnStatus ;
VAR
   status: CsnStatus ;
BEGIN
   (* again no need to disable interrupts here as RxNb and Test do it *)
   status := RxNb(t, a, l, ActualReceived) ;
   IF status=CsnOk
   THEN
      status := Test(t, CsnFlags{CsnRxReady}, MAX(CARDINAL), n, a, status) ;
      IF status=CsnRxReady
      THEN
         RETURN( CsnOk )
      END
   END ;
   RETURN( status )
END Rx ;


(*
   IsLegalNetId - returns TRUE if, n, is legal.
*)

PROCEDURE IsLegalNetId (n: NetId) : BOOLEAN ;
BEGIN
   RETURN( TRUE )
END IsLegalNetId ;


(*
   InitTxDesc - creates a new descriptor and fills it with the TxNb
                parameters and sets its state to txinit.
                The descriptor is not placed onto any queue.
*)

PROCEDURE InitTxDesc (t: Transport; n: NetId; a: ADDRESS; l: CARDINAL) : Desc ;
VAR
   d: Desc ;
BEGIN
   d := NewDesc() ;
   IF d=NIL
   THEN
      RETURN( NIL )
   ELSE
      WITH d^ DO
         Type  := tx ;
         State := txinit ;
         WITH txinfo DO
            tpt     := t ;
            WhoTo   := n ;
            WhoFrom := t^.netid ;
            Start   := a ;
            Length  := l
         END
      END ;
      RETURN( d )
   END
END InitTxDesc ;


(*
   InitRxDesc - creates a new descriptor and fills it with the RxNb
                parameters and sets its state to rxinit.
                The descriptor is not placed onto any queue.
*)

PROCEDURE InitRxDesc (t: Transport; a: ADDRESS; l: CARDINAL;
                      VAR ActualReceived: CARDINAL) : Desc ;
VAR
   d: Desc ;
BEGIN
   d := NewDesc() ;
   IF d=NIL
   THEN
      RETURN( NIL )
   ELSE
      WITH d^ DO
         Type  := rx ;
         State := rxinit ;
         WITH rxinfo DO
            tpt         := t ;
            WhoTo       := t^.netid ;    (* ourselves           *)
            WhoFrom     := NullNetId ;   (* anybody, at present *)
            Start       := a ;
            Length      := l ;
            PtrToActual := ADR(ActualReceived)
         END
      END ;
      RETURN( d )
   END
END InitRxDesc ;


(*
   TxNb - transmits a block of memory: a..a+l to address, netid.
          This function may return before the data is sent.
          The completion of this action *must* be tested by a call to
          Test.
*)

PROCEDURE TxNb (t: Transport; n: NetId; a: ADDRESS; l: CARDINAL) : CsnStatus ;
VAR
   d         : Desc ;
   Status    : CsnStatus ;
BEGIN
   IF IsLegalNetId(t^.netid)
   THEN
      IF IsLegalNetId(n)
      THEN
         d := InitTxDesc(t, n, a, l) ;
         IF d=NIL
         THEN
            Status := CsnNoHeap
         ELSE
            Status := decodeTxDesc(t, d)
         END
      ELSE
         Status := CsnIllegalNetId
      END
   ELSE
      Status := CsnUnitializedTransport
   END ;
   RETURN( Status )
END TxNb ;


(*
   RxNb - receives a block of memory from a transport address, n.
          Note that the actual number of bytes received can be smaller than
          the block of memory defined in the call to RxNb.
          If the network address is NullId then it will accept a message from
          any other transport.
          Note that the function may return before the data has been received
          and also NetId may be updated later.
          The completion of this action *must* be tested by a call to
          Test.
*)

PROCEDURE RxNb (t: Transport; a: ADDRESS; l: CARDINAL;
                VAR ActualReceived: CARDINAL) : CsnStatus ;
VAR
   d         : Desc ;
   Status    : CsnStatus ;
BEGIN
   IF IsLegalNetId(t^.netid)
   THEN
      d := InitRxDesc(t, a, l, ActualReceived) ;
      IF d=NIL
      THEN
         Status := CsnNoHeap
      ELSE
         Status := decodeRxDesc(t, d)
      END
   ELSE
      Status := CsnUnitializedTransport
   END ;
   RETURN( Status )
END RxNb ;


(*
   DecrementTimeout - decrements value, timeout, by value, by.
                      0 <= timeout < MAX(CARDINAL)-by
*)

PROCEDURE DecrementTimeout (VAR timeout: CARDINAL; by: CARDINAL) ;
BEGIN
   IF by>timeout
   THEN
      timeout := 0
   ELSE
      DEC(timeout, by)
   END
END DecrementTimeout ;


(*
   CountQ - returns the number of descriptors on a queue.
*)

PROCEDURE CountQ (q: Desc) : CARDINAL ;
VAR
   p    : Desc ;
   count: CARDINAL ;
BEGIN
   IF q=NIL
   THEN
      RETURN( 0 )
   ELSE
      count := 0 ;
      p     := q ;
      REPEAT
         INC(count) ;
         p := p^.Q.Right
      UNTIL p=q ;
      RETURN( count )
   END
END CountQ ;


(*
   CheckLegalFlags - checks the flags parameter to Test.
*)

PROCEDURE CheckLegalFlags (flags: CsnFlags) ;
BEGIN
   IF CsnFlags{CsnTxReady, CsnRxReady} * flags#flags
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'illegal flags parameter passed to Test')
   END
END CheckLegalFlags ;


(*
   FillIn - fills in all parameters from a descriptor and then
            disposes of this descriptor.
*)

PROCEDURE FillIn (VAR head: Desc; d: Desc;
                  VAR timeout: CARDINAL; VAR n: NetId;
                  VAR a: ADDRESS; VAR s: CsnStatus) ;
BEGIN
   SubFrom(head, d) ;
   WITH d^ DO
      CASE Type OF

      rx:  n := rxinfo.WhoFrom ;
           a := rxinfo.Start ;
           s := rxinfo.Status |
      tx:  n := txinfo.WhoFrom ;
           a := txinfo.Start ;
           s := txinfo.Status

      ELSE
         Halt(__FILE__, __LINE__, __FUNCTION__, 'unexpected Type value in descriptor')
      END
   END ;
   timeout := 0 ;
   d := DisposeDesc(d)
END FillIn ;


(*
   Test - tests whether a non blocking operation has completed.
          Each non blocking operation TxNb and RxNb must be followed
          (at some stage) by a call to Test. This does not have to be
          done immediately or before another call to TxNb etc.

          Given a transport, t, Test sees whether a non blocking operation
          has completed on the transport. It tests for TxReady or RxReady
          dependant upon the flags.

          The timeout value indicates how long the Test should wait:
          0                 do not wait (ie poll and return immediately)
          MAX(CARDINAL)     wait until the operation completes.
          0<n<MAX(CARDINAL) wait for n microseconds or until completion

          The most complicated of all functions in this definition module.
          The parameters are divided into two sections:
          t, flags, timeout:   refer to the actual Test.

          n, a, s          :   are filled in by test but refer to
                               the completed operation.
                               n is the netid of the transport communicating
                               with t.
                               a is the start of the block of memory which
                               has completed.
                               s is the status of the completed operation.
*)

PROCEDURE Test (t: Transport; flags: CsnFlags; timeout: CARDINAL;
                VAR n: NetId; VAR a: ADDRESS; VAR s: CsnStatus) : CsnStatus ;
VAR
   Status: CsnStatus ;
BEGIN
   WITH t^ DO
      (* firstly examine the DoneQ - as hopefully the operation
         will have completed and we can finish this Test swiftly
      *)
      CheckLegalFlags(flags) ;
      REPEAT
         Status := ForeachDescriptor(doneQ, flags, timeout, n, a, s) ;
         IF (Status=CsnOk) AND (timeout=MAX(CARDINAL))
         THEN
            (* nothing found and we need to wait *)
            CASE flags OF

            CsnFlags{}:  Halt(__FILE__, __LINE__, __FUNCTION__, 'user wants to block forever..') |
            CsnFlags{CsnRxReady}:  block(RxQ) |
            CsnFlags{CsnTxReady}:  block(TxQ) |
            CsnFlags{CsnTxReady, CsnRxReady}:  block(TxRxQ)

            ELSE
               Halt(__FILE__, __LINE__, __FUNCTION__, 'unknown flag combination')
            END
         END
      UNTIL (Status#CsnOk) OR (timeout=0)
   END ;
   (* all done and we return the status *)
   RETURN( Status )
END Test ;


(*
   ForeachDescriptor - foreach descriptor on q, test for a match
                       given parameters, t, flags, timeout, n, a, s.
*)

PROCEDURE ForeachDescriptor (VAR doneQ: Desc; flags: CsnFlags;
                             VAR timeout: CARDINAL; VAR n: NetId;
                             VAR a: ADDRESS; VAR s: CsnStatus) : CsnStatus ;
VAR
   p: Desc ;
BEGIN
   IF doneQ#NIL
   THEN
      p := doneQ ;
      REPEAT
         CASE p^.Type OF

         rx:  IF (a=NIL) OR (a=p^.rxinfo.Start)
              THEN
                 (* address matches the descriptor buffer *)
                 IF CsnRxReady IN flags
                 THEN
                    (*
                       flags match the descriptor on DoneQ
                       (note CsnRxReady)
                    *)
                    FillIn(doneQ, p, timeout, n, a, s) ;
                    RETURN( CsnRxReady )
                 END
              END |
         tx:  IF (a=NIL) OR (a=p^.txinfo.Start)
              THEN
                 (* address matches the descriptor buffer *)
                 IF CsnTxReady IN flags
                 THEN
                    (*
                       flags match the descriptor on DoneQ
                       (note CsnTxReady)
                    *)
                    FillIn(doneQ, p, timeout, n, a, s) ;
                    RETURN( CsnTxReady )
                 END
              END

         ELSE
            Halt(__FILE__, __LINE__, __FUNCTION__, 'unexpected Type in descriptor')
         END ;
         p := p^.Q.Right
      UNTIL doneQ=p
   END ;
   RETURN( CsnOk )
END ForeachDescriptor ;


(*
   Init - initialize this modules local variables.
*)

PROCEDURE Init ;
BEGIN
   (* atexit(ListenLoop) ; *)
   DescNo := 0 ;
   freeDesc := NIL ;
   nsstate := unknown ;
   remoteName := NIL ;
   debugging := (getenv(ADR('CSN_DEBUG'))#NIL) ;
   IF getenv(ADR('CSN_NAMESERVER'))=NIL
   THEN
      nameServer
   ELSE
      resolvConf(getenv(ADR('CSN_NAMESERVER')))
   END
END Init ;


BEGIN
   Init
END csn.
