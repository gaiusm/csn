(* Copyright (C) 2005 Free Software Foundation, Inc. *)
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
Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA. *)

IMPLEMENTATION MODULE execArgs ;

FROM SYSTEM IMPORT ADDRESS, BYTE, ADR ;
FROM Debug IMPORT Halt ;
FROM libc IMPORT memcpy ;
FROM Executive IMPORT SEMAPHORE, InitSemaphore, Wait, Signal ;

VAR
   argQueue,
   argReady,
   argTaken: SEMAPHORE ;
   argument: ADDRESS ;
   nBytes  : CARDINAL ;


(*
   beginPutArg - 
*)

PROCEDURE beginPutArg (VAR a: ARRAY OF BYTE) ;
BEGIN
   Wait(argQueue) ;
   argument := ADR(a) ;
   nBytes := HIGH(a)+1 ;
   Signal(argReady) ;
END beginPutArg ;


(*
   endPutArg - 
*)

PROCEDURE endPutArg ;
BEGIN
   Wait(argTaken) ;
   Signal(argQueue)
END endPutArg ;


(*
   getArg - 
*)

PROCEDURE getArg (VAR a: ARRAY OF BYTE) ;
VAR
   b: ADDRESS ;
BEGIN
   Wait(argReady) ;
   IF HIGH(a)+1#nBytes
   THEN
      Halt(__FILE__, __LINE__, __FUNCTION__, "incorrect size of argument")
   END ;
   b := memcpy(ADR(a), argument, nBytes) ;
   Signal(argTaken)
END getArg ;


BEGIN
   argQueue := InitSemaphore(1, 'argQueue') ;
   argReady := InitSemaphore(0, 'argReady') ;
   argTaken := InitSemaphore(0, 'argTaken')
END execArgs.
