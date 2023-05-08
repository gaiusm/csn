MODULE ex2 ;

FROM SYSTEM IMPORT ADDRESS, TurnInterrupts, ADR ;
FROM COROUTINES IMPORT PROTECTION ;
FROM Debug IMPORT Halt ;
FROM StrLib IMPORT StrLen, StrCopy ;
FROM libc IMPORT printf ;
FROM Executive IMPORT DESCRIPTOR, InitProcess, Resume ;
FROM csn IMPORT Transport, NetId, CsnStatus, NullNetId, Rx, Tx ;
FROM Args IMPORT GetArg ;

IMPORT csn ;


(*
   Sink - receives a single string from the Source process.
*)

PROCEDURE Sink ;
VAR
   tpt   : Transport ;
   actual: CARDINAL ;
   netid : NetId ;
   status: CsnStatus ;
   bufptr: ADDRESS ;
   buffer: ARRAY [0..80] OF CHAR ;
BEGIN
   IF csn.Open(tpt) # CsnOk
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to open transport')
   END ;

   (* we register our transport *)
   IF csn.RegisterName(tpt, 'sink') # CsnOk
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to register name')
   END ;

   LOOP
      IF csn.RxNb(tpt, ADR(buffer), HIGH(buffer), actual) # CsnOk
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to queue buffer')
      END ;

      netid  := NullNetId ;
      bufptr := NIL ;
      CASE csn.Test(tpt, csn.CsnFlags{CsnRxReady}, MAX(CARDINAL),
                    netid, bufptr, status)
      OF

      CsnRxReady:  printf(buffer) ; printf(" \n")

      ELSE
         Halt(__FILE__, __LINE__, __FUNCTION__, 'unexpected return value from csn.Test')
      END
   END
END Sink ;


(*
   Source - sends a single string to the Source process.
*)

PROCEDURE Source ;
VAR
   tpt   : Transport ;
   sinkId: NetId ;
   status: CsnStatus ;
   buffer: ARRAY [0..80] OF CHAR ;
BEGIN
   IF csn.Open(tpt) # CsnOk
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to open transport')
   END ;

   IF csn.LookupName (sinkId, 'sink') # CsnOk
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to lookup sink netid')
   END ;
   LOOP
      StrCopy('Hello ', buffer) ;

      status := csn.Tx(tpt, sinkId, ADR(buffer), StrLen(buffer)+1) ;
      IF status#CsnOk
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to send string to sink process')
      END ;
      StrCopy('world', buffer) ;
      status := csn.Tx(tpt, sinkId, ADR(buffer), StrLen(buffer)+1) ;
      IF status#CsnOk
      THEN
         Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to send string to sink process')
      END
   END
END Source ;


(*
   Init - starts the process and becomes the Sink process.
*)

PROCEDURE Init ;
VAR
   source    : DESCRIPTOR ;
   ToOldState: PROTECTION ;
   a         : ARRAY [0..1] OF CHAR ;
BEGIN
   ToOldState := TurnInterrupts(MIN(PROTECTION)) ;
   IF GetArg(a, 1)
   THEN
      Sink
   ELSE
      Source
   END
END Init ;


BEGIN
   Init
END ex2.
