
#define CSN_C
#include "csn.h"
#include <string.h>

#if !defined(TRUE)
#  define TRUE (1==1)
#endif

#if !defined(FALSE)
#  define FALSE (1==0)
#endif


extern csn_status csn_Open (transport *t);
extern csn_status csn_Close (transport *t);
extern csn_status csn_RegisterName (transport t, char *name, unsigned int len);
extern csn_status csn_LookupName (netid *n, char *name, unsigned int len);
extern csn_status csn_Tx (transport t, netid n, void *a, unsigned int l);
extern csn_status csn_Rx (transport t, netid *n, void *a, unsigned int l,
			  unsigned int *actualReceived);
extern csn_status csn_TxNb (transport t, netid n, void *a, unsigned int l);
extern csn_status csn_RxNb (transport t, void *a, unsigned int l, unsigned int *actual);
extern csn_status csn_Test (transport t, csn_flags flags, unsigned int timeout,
			    netid n, void *a, csn_status s);


extern void _M2_Storage_init (int argc, char **argv);
extern void _M2_SYSTEM_init (int argc, char **argv);
extern void _M2_M2RTS_init (int argc, char **argv);
extern void _M2_RTExceptions_init (int argc, char **argv);
extern void _M2_M2EXCEPTION_init (int argc, char **argv);
extern void _M2_SysExceptions_init (int argc, char **argv);
extern void _M2_SysStorage_init (int argc, char **argv);
extern void _M2_Assertion_init (int argc, char **argv);
extern void _M2_ASCII_init (int argc, char **argv);
extern void _M2_StrLib_init (int argc, char **argv);
extern void _M2_DynamicStrings_init (int argc, char **argv);
extern void _M2_NumberIO_init (int argc, char **argv);
extern void _M2_FIO_init (int argc, char **argv);
extern void _M2_errno_init (int argc, char **argv);
extern void _M2_termios_init (int argc, char **argv);
extern void _M2_IO_init (int argc, char **argv);
extern void _M2_Indexing_init (int argc, char **argv);
extern void _M2_StdIO_init (int argc, char **argv);
extern void _M2_Selective_init (int argc, char **argv);
extern void _M2_COROUTINES_init (int argc, char **argv);
extern void _M2_StrIO_init (int argc, char **argv);
extern void _M2_NameKey_init (int argc, char **argv);
extern void _M2_Executive_init (int argc, char **argv);
extern void _M2_Debug_init (int argc, char **argv);
extern void _M2_Lock_init (int argc, char **argv);
extern void _M2_SymbolKey_init (int argc, char **argv);
extern void _M2_UnixArgs_init (int argc, char **argv);
extern void _M2_execArgs_init (int argc, char **argv);
extern void _M2_RTint_init (int argc, char **argv);
extern void _M2_SysTypes_init (int argc, char **argv);
extern void _M2_SocketControl_init (int argc, char **argv);
extern void _M2_sckt_init (int argc, char **argv);
extern void _M2_Args_init (int argc, char **argv);
extern void _M2_csn_init (int argc, char **argv);


static int initialized = FALSE;


static void check_initialised (void)
{
  if (! initialized) {
    initialized = TRUE;
    _M2_Storage_init (0, NULL);
    _M2_SYSTEM_init (0, NULL);
    _M2_M2RTS_init (0, NULL);
    _M2_RTExceptions_init (0, NULL);
    _M2_M2EXCEPTION_init (0, NULL);
    _M2_SysExceptions_init (0, NULL);
    _M2_SysStorage_init (0, NULL);
    _M2_Assertion_init (0, NULL);
    _M2_ASCII_init (0, NULL);
    _M2_StrLib_init (0, NULL);
    _M2_DynamicStrings_init (0, NULL);
    _M2_NumberIO_init (0, NULL);
    _M2_FIO_init (0, NULL);
    _M2_errno_init (0, NULL);
    _M2_termios_init (0, NULL);
    _M2_IO_init (0, NULL);
    _M2_Indexing_init (0, NULL);
    _M2_StdIO_init (0, NULL);
    _M2_Selective_init (0, NULL);
    _M2_COROUTINES_init (0, NULL);
    _M2_StrIO_init (0, NULL);
    _M2_NameKey_init (0, NULL);
    _M2_Executive_init (0, NULL);
    _M2_Debug_init (0, NULL);
    _M2_Lock_init (0, NULL);
    _M2_SymbolKey_init (0, NULL);
    _M2_UnixArgs_init (0, NULL);
    _M2_execArgs_init (0, NULL);
    _M2_RTint_init (0, NULL);
    _M2_SysTypes_init (0, NULL);
    _M2_SocketControl_init (0, NULL);
    _M2_sckt_init (0, NULL);
    _M2_Args_init (0, NULL);
    _M2_csn_init (0, NULL);
  }
}

csn_status csn_open (transport *t)
{
  check_initialised();
  return csn_Open (t);
}


csn_status csn_close (transport *t)
{
  check_initialised();
  return csn_Close (t);
}


csn_status csn_registername (transport t, char *name)
{
  check_initialised();
  return csn_RegisterName (t, name, strlen (name));
}


csn_status csn_lookupname (netid *n, char *name)
{
  check_initialised();
  return csn_LookupName (n, name, strlen(name));
}


csn_status csn_tx (transport t, netid n, void *a, unsigned int l)
{
  check_initialised();
  return csn_Tx (t, n, a, l);
}


csn_status csn_rx (transport t, netid *n, void *a, unsigned int l,
		   unsigned int *actualReceived)
{
  check_initialised();
  return csn_Rx (t, n, a, l, actualReceived);
}


csn_status csn_txnb (transport t, netid n, void *a, unsigned int l)
{
  check_initialised();
  return csn_TxNb (t, n, a, l);
}


csn_status csn_rxnb (transport t, void *a, unsigned int l,
		     unsigned int *actualReceived)
{
  check_initialised();
  return csn_RxNb (t, a, l, actualReceived);
}


csn_status csn_test (transport t, csn_flags flags, unsigned int timeout,
		     netid n, void *a, csn_status s)
{
  check_initialised();
  return csn_Test (t, flags, timeout, n, a, s);
}
