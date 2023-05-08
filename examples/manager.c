/* tiny.c
 *	Copyright (C) 2010 Free Software Foundation, Inc.
 *
 * This file is part of libcsn.
 *
 * libcsn is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of
 * the License, or (at your option) any later version.
 *
 * libcsn is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <gcrypt.h>
#include <limits.h>
#include <csn.h>


#define MAX_DATA_LEN 100

static char key[MAX_DATA_LEN];
static unsigned char ciphertext[MAX_DATA_LEN];
static unsigned char plaintext[MAX_DATA_LEN];
static int nWorkers = 0;


/*
 *  setupCiphertext - sets up nWorkers, ciphertext, key and plaintext.
 */

static void setupCiphertext (int argc, char *argv[])
{
  gcry_cipher_hd_t hd;
  int i, blklen, keylen;
  gcry_error_t err = 0;

  strcpy (plaintext, "This is a sample plaintext for CBC MAC of sixtyfour bytes.......");

  err = gcry_cipher_open (&hd,
			  GCRY_CIPHER_DES,
			  GCRY_CIPHER_MODE_CBC, GCRY_CIPHER_CBC_MAC);
  if (hd == NULL)
    debugf ("cbc-mac algo DES, grcy_open_cipher failed\n");

  blklen = gcry_cipher_get_algo_blklen (GCRY_CIPHER_DES);
  if (blklen == 0)
    debugf ("cbc-mac algo DES, gcry_cipher_get_algo_blklen failed\n");

  keylen = gcry_cipher_get_algo_keylen (GCRY_CIPHER_DES);
  printf("key size %d bytes\n", blklen);
  if (keylen == 0)
    debugf ("cbc-mac algo DES, gcry_cipher_get_algo_keylen failed\n");

  if (argc == 1) {
    printf("%s requires a key of length %d bytes as the first argument\n",
	   argv[0], keylen);
    exit(1);
  }

  if (strlen (argv[1]) < keylen) {
    printf("%s requires a key of length %d bytes as the first argument\n",
	   argv[0], keylen);
    exit(1);
  }
  strcpy (key, argv[1]);

  if (argc == 3)
    nWorkers = atoi (argv[2]);
  else {
    printf("%s requires the number of worker processes as the second argument\n",
	   argv[0]);
    exit (1);
  }

  err = gcry_cipher_setkey (hd, key, keylen);
  if (err != 0)
    debugf ("cbc-mac algo DES, gcry_cipher_setkey failed:\n");

  err = gcry_cipher_setiv (hd, NULL, 0);
  if (err != 0)
    debugf ("cbc-mac algo DES, gcry_cipher_setiv failed:\n");

  err = gcry_cipher_encrypt (hd,
			     ciphertext, blklen,
			     plaintext,
			     strlen (plaintext));
  if (err)
    debugf ("cbc-mac algo DES, gcry_cipher_encrypt failed\n");

  gcry_cipher_close (hd);
}


static void printTexts (void)
{
  int i;

  printf("plaintext =%s\n", plaintext);
  printf("ciphertext=");
  for (i = 0; i<strlen(plaintext); i++)
    printf("%2x ", ciphertext[i]);
  printf("\n");
}

/*
 *  deligateWork - see if the workers can brute force the key given plaintext
 *                 and ciphertext.
 */

static void deligateWork (void)
{
  transport  t;
  csn_status status;
  netid     *workerId = (netid *) alloca (sizeof(netid)*nWorkers);
  char       name[80];
  char       theanswer[MAX_DATA_LEN];
  netid      w;
  int        nBytes;
  int        i;

  if (workerId == NULL)
    perror("malloc");

  status = csn_open (&t);
  if (status != CsnOk)
    debugf("csn_open failed");

  status = csn_registername (t, "manager");  /* register our transport.  */
  for (i=1; i<=nWorkers; i++) {
    snprintf (name, 80, "worker%d", i);
    status = csn_lookupname (&workerId[i], name);
    if (status != CsnOk)
      debugf ("failed to lookupname");
  }
  /* send plaintext and ciphertext to each worker.  */
  for (i = 1; i <= nWorkers; i++) {
    status = csn_tx(t, workerId[i], plaintext, MAX_DATA_LEN);
    status = csn_tx(t, workerId[i], ciphertext, MAX_DATA_LEN);
  }
  /* now wait for a reply for each worker.  */
  for (i = 1; i <= nWorkers; i++) {
    /* the order of replies does not matter.  */
    w = csn_nullnetid;
    printf ("waiting for a reply\n");
    status = csn_rx (t, &w, theanswer, MAX_DATA_LEN, &nBytes);
    printf ("got reply..\n");
    if (strlen (theanswer) == 0)
      printf ("but it was not cracked by that processor\n");
    else
      printf ("\nyes the key has been cracked and it is: %s\n", theanswer);
  }
}

int
main (int argc, char *argv[])
{
  setupCiphertext (argc, argv);
  printTexts ();
  deligateWork ();
}
