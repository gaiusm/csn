MODULE ex1 ;

FROM SYSTEM IMPORT ADDRESS, TurnInterrupts, ADR ;
FROM COROUTINES IMPORT PROTECTION ;
FROM csn IMPORT Transport, NetId, CsnStatus, NullNetId, Rx, Tx ;
FROM M2RTS IMPORT Halt ;
FROM StrLib IMPORT StrLen, StrCopy ;
FROM libc IMPORT printf, getenv ;
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
   buffer: ARRAY [0..80] OF CHAR ;
   r     : INTEGER ;
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

   netid  := NullNetId ;
   status := Rx(tpt, netid, ADR(buffer), HIGH(buffer), actual) ;
   IF status=CsnOk
   THEN
      r := printf('sink received string: %s\n', buffer)
   ELSE
      Halt(__FILE__, __LINE__, __FUNCTION__, 'Rx failed')
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
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to lookup filter program')
   END ;
    
   StrCopy('Hello world', buffer) ;

   status := csn.Tx(tpt, sinkId, ADR(buffer), StrLen(buffer)+1) ;
   IF status#CsnOk
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, 'failed to send string to sink process')
   END
END Source ;


(*
   Init - starts the process and becomes the Sink process.
*)

PROCEDURE Init ;
VAR
   ToOldState: PROTECTION ;
   a         : ARRAY [0..1] OF CHAR ;
BEGIN
   ToOldState := TurnInterrupts(MIN(PROTECTION)) ;
   IF GetArg(a, 1)
   THEN
      Source
   ELSE
      Sink
   END
END Init ;


BEGIN
   Init
END ex1.
