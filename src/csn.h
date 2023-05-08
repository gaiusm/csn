/*
 *   csn.h - prototypes for the csn reimplementation.
 */

#if defined(CSN_C)
#   define EXTERN
#else
#   define EXTERN extern
#endif

typedef void* transport;

typedef struct netid_t {
  unsigned int ip;
  unsigned int port;
} netid;

typedef enum {CsnTxReady, CsnRxReady, CsnTimeout, CsnOk, CsnNoHeap,
              CsnIllegalNetId, CsnUnitializedTransport,
              CsnNetIdAlreadyRegistered, CsnOverrun, CsnBusy} csn_status;

typedef unsigned int csn_flags;

#define debugf(X)   printf("%s:%d in function %s %s\n", __FILE__, __LINE__, __FUNCTION__, X)

#define csn_nullnetid (netid){0,0}


/*
 *  open - creates a new transport, t, and returns status.
 */

EXTERN csn_status csn_open (transport *t);


/*
 *  close - closes a transport, t, and returns status.
 */

EXTERN csn_status csn_close (transport *t);


/*
 *  registername - gives a, name, to transport, t, which can later be
 *                 looked up by another process.
 */

EXTERN csn_status csn_registername (transport t, char *name);


/*
 *  lookupname - blocks until a netid, n, becomes registered with, name.
 */

EXTERN csn_status csn_lookupname (netid *n, char *name);


/*
 *  tx - transmits a block of memory to a network address, n.
 *       The block of memory is defined as: a..a+l.
 */

EXTERN csn_status csn_tx (transport t, netid n, void *a, unsigned int l);


/*
 *  rx - receives a message into a block of memory from a network address, n.
 *       Note that the actual number of bytes received can be smaller than
 *       the block of memory defined in the call to Rx.
 *       If the network address is NullId then it will accept a message from
 *       any other transport. When the function returns NetId will contain
 *       the netid of the sender.
 */

EXTERN csn_status csn_rx (transport t, netid *n, void *a, unsigned int l,
			  unsigned int *actualReceived);


/*
 *  txnb - transmits a block of memory: a..a+l to address, netid.
 *         This function may return before the data is sent.
 *         The completion of this action *must* be tested by a call to
 *         csn_test.
 */

EXTERN csn_status txnb (transport t, netid n, void *a, unsigned int l);


/*
 *  rxnb - receives a block of memory from a transport address, netid.
 *         Note that the actual number of bytes received can be smaller than
 *         the block of memory defined in the call to RxNb.
 *         If the network address is NullId then it will accept a message from
 *         any other transport.
 *         Note that the function may return before the data has been received
 *         and also NetId may be updated later.
 *         The completion of this action *must* be tested by a call to
 *         csn_test.
 */

EXTERN csn_status rxnb (transport t, void *a, unsigned int l,
			unsigned int *actualReceived);


/*
 *  test - tests whether a non blocking operation has completed.
 *         Each non blocking operation TxNb and RxNb must be followed
 *         (at some stage) by a call to Test. This does not have to be
 *         done immediately or before another call to TxNb etc.
 *
 *         Given a transport, t, Test sees whether a non blocking operation
 *         has completed on the transport. It tests for TxReady or RxReady
 *         dependant upon the flags.
 *
 *         The timeout value indicates how long the Test should wait:
 *         0                 do not wait (ie poll and return immediately)
 *         MAX(CARDINAL)     wait until the operation completes.
 *         0<n<MAX(CARDINAL) wait for n microseconds or until completion
 *
 *         The most complicated of all functions in this definition module.
 *         The parameters are divided into two sections:
 *         t, flags, timeout:   refer to the actual Test.
 *
 *         n, a, s          :   are filled in by test but refer to
 *                              the completed operation.
 *                              n is the netid of the transport communicating
 *                              with t.
 *                              a is the start of the block of memory which
 *                              has completed.
 *                              s is the status of the completed operation.
 */

EXTERN csn_status csn_test (transport t, csn_flags flags, unsigned int timeout,
			    netid n, void *a, csn_status s);


/*
 * nameServer - temporary hack, indicates that the caller is the cs name server.
 */

EXTERN void csn_nameserver (char *name);


/*
 *  resolvConf - tells the csn subsystem to use, name, as the
 *               cs name server. Not the same as a real IP name server.
 */

EXTERN void csn_resolvconf (char *name);

#undef EXTERN
