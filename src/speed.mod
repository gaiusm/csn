MODULE speed ;


FROM SYSTEM IMPORT ADDRESS, TurnInterrupts ;
FROM COROUTINES IMPORT PROTECTION ;
FROM SysStorage IMPORT ALLOCATE ;
FROM Debug IMPORT Halt ;
FROM StrLib IMPORT StrConCat, StrEqual ;
FROM NumberIO IMPORT CardToStr ;
FROM libc IMPORT memset, printf, timeb, ftime, perror ;
FROM Executive IMPORT DESCRIPTOR, InitProcess, Resume ;
FROM Args IMPORT GetArg ;
FROM Assertion IMPORT Assert ;

FROM csn IMPORT Transport, NetId, CsnStatus, CsnFlags, NullNetId,
                Rx, Tx, RxNb, TxNb ;

IMPORT csn ;


CONST
   BytesToBeSent    = 100*1024 ;
   MaxCharString    =   1024 ;
   MaxCount         =  10000 ;
   MaxSinks         =      1 ;
   MaxFilterBuffers =      1 ;
   StackSize        = 10*1024*1024 ;
   Debugging        = FALSE ;


(*
   Filter - a process which opens up a transport and waits for
            a number of messages. Whenever a message arrives
            it performs some filtering on the message and then
            transmits it to the sink process.
*)

PROCEDURE Filter ;
VAR
   tpt    : Transport ;
   netid  : NetId ;
   sinkIds: ARRAY [0..MaxSinks-1] OF NetId ;
   name   : ARRAY [0..MaxCharString] OF CHAR ;
   sink   : CARDINAL ;
   buffer : ADDRESS ;
   status : CsnStatus ;
   actual,
   i      : CARDINAL ;
   p      : POINTER TO CARDINAL ;
BEGIN
   IF csn.Open(tpt) # CsnOk
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to open transport')
   END ;

   IF csn.RegisterName (tpt, 'filter') # CsnOk
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to register name')
   END ;

   FOR sink := 0 TO MaxSinks-1 DO
      CardToStr(sink, 0, name) ;
      StrConCat('sink', name, name) ;

      IF csn.LookupName (sinkIds[sink], name) # CsnOk
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to lookup sink')
      END
   END ;

   FOR i := 1 TO MaxFilterBuffers DO
      ALLOCATE(buffer, BytesToBeSent) ;
      IF buffer=NIL
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to allocate buffer')
      END ;

      IF csn.RxNb(tpt, buffer, BytesToBeSent, actual) # CsnOk
      THEN
	 Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to queue buffer (initially)')
      END
   END ;

   sink := 0 ;
   i := 0 ;
   LOOP
      buffer := NIL ;
      netid  := NullNetId ;

      CASE csn.Test(tpt, csn.CsnFlags{CsnRxReady, CsnTxReady}, MAX(CARDINAL),
                    netid, buffer, status)
      OF

      CsnTxReady:
          IF Debugging
          THEN
             p := buffer ;
             printf('filter *** has sent packet 0x%x %d\n', buffer, p^)
          END ;
          IF csn.RxNb(tpt, buffer, BytesToBeSent, actual) # CsnOk
          THEN
             Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to requeue receive')
          END |
      CsnRxReady:
          (* do some filtering on buffer - for now we zap it to zero *)
          (* buffer := memset(buffer, 0, BytesToBeSent) ; *)
          (* now transmit it to the next process (a sink) *)
          IF Debugging
          THEN
             p := buffer ;
             printf('filter ### is about to send packet 0x%x %d\n', buffer, p^)
          END ;
          IF csn.TxNb(tpt, sinkIds[sink], buffer, BytesToBeSent) # CsnOk
          THEN
             Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to queue buffer on transmit')
          END ;
          sink := (sink+1) MOD MaxSinks

       ELSE
          Halt(__FILE__, __LINE__, __FUNCTION__, 'csn.Test failed')
       END
    END
END Filter ;


(*
   Sink - a process which continually grabs a message and
          displays performance statistics.
*)

PROCEDURE Sink ;
VAR
   tpt   : Transport ;
   actual,
   count : CARDINAL ;
   tnow,
   tstart: timeb ;
   buffer: ADDRESS ;
   netid : NetId ;
   status: CsnStatus ;
   mb    : LONGCARD ;
   t     : CARDINAL ;
   p     : POINTER TO CARDINAL ;
   l     : CARDINAL ;
BEGIN
   IF csn.Open(tpt) # CsnOk
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to open transport')
   END ;

   (* should really know our own sink id and register the appropriate name *)
   IF csn.RegisterName(tpt, 'sink0') # CsnOk
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to register name')
   END ;

   ALLOCATE(buffer, BytesToBeSent) ;
   IF buffer=NIL
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to allocate buffers')
   END ;


   count := 0 ;
   l := 1 ;
   printf('sink started, waiting for data to arrive\n') ;
   LOOP
      netid  := NullNetId ;
      status := Rx(tpt, netid, buffer, BytesToBeSent, actual) ;
      p := buffer ;
      IF p^=count
      THEN
         IF Debugging
         THEN
            printf("received packet %d\n", p^)
         END
      ELSE
         printf("received packet %d should have been %d  (actual bytes received=%d)\n",
                p^, count, actual)
      END ;
      IF count=0
      THEN
         IF ftime(tstart) = -1
         THEN
            perror("ftime")
         END
      END ;

      IF count=l
      THEN
         printf('pkt %d\n', count) ;
         l := l*10
      END ;
      IF count=MaxCount
      THEN
         IF ftime(tnow) = -1
         THEN
            perror("ftime")
         END ;
         t := VAL(CARDINAL, tnow.time)*1000+VAL(CARDINAL, tnow.millitm)-
              VAL(CARDINAL, tstart.time)*1000+VAL(CARDINAL, tstart.millitm) ;
         printf("time to send %6d blocks of %6d bytes is %d.%03d seconds\n",
                count, BytesToBeSent, t DIV 1000, t MOD 1000) ;
(*  wrong
         mb := (VAL(LONGCARD, count) * VAL(LONGCARD, BytesToBeSent) * 1000) DIV
               VAL(LONGCARD, t) ;
         printf(" %d.%6d MBytes/Second\n",
                VAL(CARDINAL, mb DIV (1024*1024)), VAL(CARDINAL, mb MOD (1024*1024))) ;
*)
         count  := 0 ;
         tstart := tnow ;
         printf('speed test finished successfully\n')
      ELSE
         INC(count)
      END
   END
END Sink ;


(*
   Source - continually transmits packets to the filter process.
*)

PROCEDURE Source ;
VAR
   tpt     : Transport ;
   buffer  : ADDRESS ;
   filterId: NetId ;
   status  : CsnStatus ;
   p       : POINTER TO CARDINAL ;
   i       : CARDINAL ;
BEGIN
   IF csn.Open(tpt) # CsnOk
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to open transport')
   END ;

   IF csn.LookupName (filterId, 'filter') # CsnOk
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to lookup filter program')
   END ;

   ALLOCATE(buffer, BytesToBeSent) ;
   IF buffer=NIL
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to allocate buffer')
   END ;

   p := buffer ;
   i := 0 ;
   LOOP
      p^ := i ;
      status := csn.Tx(tpt, filterId, buffer, BytesToBeSent) ;
      IF status#CsnOk
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to send to filter process')
      END ;
      IF i=MaxCount
      THEN
         i := 0
      ELSE
         INC(i)
      END
   END
END Source ;


(*
   Init - starts the process and becomes the Sink process.
*)

PROCEDURE Init ;
VAR
   filter,
   source    : DESCRIPTOR ;
   ToOldState: PROTECTION ;
   a         : ARRAY [0..2] OF CHAR ;
BEGIN
   ToOldState := TurnInterrupts(MIN(PROTECTION)) ;
   IF GetArg(a, 1) AND StrEqual(a, '0')
   THEN
      Sink
   ELSIF GetArg(a, 1) AND StrEqual(a, '1')
   THEN
      Filter
   ELSE
      Source
   END
END Init ;


BEGIN
   Init
END speed.
