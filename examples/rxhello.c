#include <csn.h>
#include <stdio.h>
#include <stdlib.h>

int
main()
{
  transport    tpt;
  unsigned int actual;
  netid        id;
  csn_status   status;
  char         buffer[80];

  if (csn_open (&tpt) != CsnOk)
    debugf ("failed to open transport");

  /* we register our transport.  */
  if (csn_registername (tpt, "sink") != CsnOk)
    debugf ("failed to register name");

  id = csn_nullnetid;   /* receive from anyone.  */
  status = csn_rx (tpt, &id, &buffer, sizeof (buffer), &actual) ;

  if (status == CsnOk)
    printf ("sink received string: %s containing %d bytes\n", buffer, actual);
  else
    debugf ("csn_rx failed");
  exit (0);
}
