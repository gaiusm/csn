%module csn

%{
typedef void* transport;

typedef struct netid_t {
  unsigned int ip;
  unsigned int port;
} netid;

typedef enum {CsnTxReady, CsnRxReady, CsnTimeout, CsnOk, CsnNoHeap,
              CsnIllegalNetId, CsnUnitializedTransport,
              CsnNetIdAlreadyRegistered, CsnOverrun} csn_status;

typedef unsigned int csn_flags;

#define debugf(X)   printf("%s:%d% in function %s %s\n", __FILE__, __LINE__, __FUNCTION__, X)

#define csn_nullnetid (netid){0,0}

csn_status csn_open (transport *t);
csn_status csn_close (transport *t);
csn_status csn_registername (transport t, char *name);
csn_status csn_lookupname (netid *n, char *name);
csn_status csn_tx (transport t, netid n, void *a, unsigned int l);
csn_status csn_rx (transport t, netid *n, void *a, unsigned int l,
                   unsigned int *actualReceived);
csn_status txnb (transport t, netid n, void *a, unsigned int l);
csn_status rxnb (transport t, void *a, unsigned int l,
                 unsigned int *actualReceived);
csn_status csn_test (transport t, csn_flags flags, unsigned int timeout,
                     netid n, void *a, csn_status s);
void csn_nameserver (char *name);
void csn_resolvconf (char *name);
%}

typedef void* transport;

typedef struct netid_t {
  unsigned int ip;
  unsigned int port;
} netid;

typedef enum {CsnTxReady, CsnRxReady, CsnTimeout, CsnOk, CsnNoHeap,
              CsnIllegalNetId, CsnUnitializedTransport,
              CsnNetIdAlreadyRegistered, CsnOverrun} csn_status;

typedef unsigned int csn_flags;

#define debugf(X)   printf("%s:%d% in function %s %s\n", __FILE__, __LINE__, __FUNCTION__, X)

#define csn_nullnetid (netid){0,0}

csn_status csn_open (transport *OUTPUT);
csn_status csn_close (transport *INOUT);
csn_status csn_registername (transport INPUT, char *INPUT);
csn_status csn_lookupname (netid *OUTPUT, char *INPUT);
csn_status csn_tx (transport t, netid n, void *a, unsigned int l);
csn_status csn_rx (transport t, netid *n, void *a, unsigned int l,
                   unsigned int *actualReceived);
csn_status txnb (transport t, netid n, void *a, unsigned int l);
csn_status rxnb (transport t, void *a, unsigned int l,
                 unsigned int *actualReceived);
csn_status csn_test (transport t, csn_flags flags, unsigned int timeout,
                     netid n, void *a, csn_status s);
void csn_nameserver (char *name);
void csn_resolvconf (char *name);
