#include <csn.h>
#include <stdio.h>
#include <string.h>

main()
{
  transport  tpt;
  netid      filterId;
  csn_status status;
  char      *buffer;
  int        i;

  if (csn_open(&tpt) != CsnOk)
    debugf("failed to open transport");

  if (csn_lookupname (filterId, "filter") != CsnOk)
    debugf("failed to lookup filter netid");

  buffer = (char *)malloc (bytesToBeSent);
  if (buffer == NULL)
    debugf("malloc failed");

  i = 0;
  p = (unsigned int *)buffer;
  while (i < NO_PACKETS) {
    *p = i;

    status = csn_tx(tpt, filterId, buffer, bytesToBeSent);
    if (status != CsnOk)
      debugf("failed to send string to filter process");

    i++;
  }
}
