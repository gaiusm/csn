MODULE nameserver ;

FROM SYSTEM IMPORT TurnInterrupts, ADR ;
FROM COROUTINES IMPORT PROTECTION ;
FROM M2RTS IMPORT Halt ;
FROM Executive IMPORT Suspend ;
FROM libc IMPORT getenv, printf ;

IMPORT csn ;


VAR
   ToOldState: PROTECTION ;
BEGIN
   ToOldState := TurnInterrupts (MIN (PROTECTION)) ;
   IF getenv (ADR ('CSN_NAMESERVER'))=NIL
   THEN
      printf ("nameserver is ready\n") ;
      Suspend ;
      Halt (__FILE__, __LINE__, __FUNCTION__, 'nameserver finished')
   ELSE
      Halt (__FILE__, __LINE__, __FUNCTION__, 'the nameserver process must not have the environment variable CSN_NAMESERVER set')
   END
END nameserver.
