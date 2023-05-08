#include <csn.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int
main ()
{
  transport  tpt;
  netid      sinkId;
  csn_status status;
  char       buffer[80];

  if (csn_open (&tpt) != CsnOk)
    debugf ("failed to open transport");

  if (csn_lookupname (&sinkId, "sink") != CsnOk)
    debugf ("failed to lookup filter program");

  strcpy (buffer, "Hello world");

  status = csn_tx (tpt, sinkId, &buffer, strlen (buffer) + 1);
  if (status != CsnOk)
    debugf ("failed to send string to sink process");
  exit (0);
}
