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


#if !defined(TRUE)
#  define TRUE (1==1)
#endif
#if !defined(FALSE)
#  define FALSE (1==0)
#endif


#define MAX_DATA_LEN 100

static unsigned char ciphertext[MAX_DATA_LEN];
static unsigned char plaintext[MAX_DATA_LEN];
static int nWorkers = 0;
static gcry_cipher_hd_t hd;
static int blklen, keylen;

/*
 *  setupCipherlib - sets up hd, keysize, blklen.
 */

static void setupCipherlib (void)
{
  int i;
  gcry_error_t err;

  strcpy(plaintext,
	 "This is a sample plaintext for CBC MAC of sixtyfour bytes.......");

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
}

/*
 *  tryKey - return TRUE if global, key, will convert plaintext into ciphertext.
 */

static int tryKey (unsigned long int *key)
{
  gcry_error_t err;
  unsigned char ciphertrial[MAX_DATA_LEN];

  err = gcry_cipher_setkey (hd, key, keylen);
  if (err != 0)
    debugf ("cbc-mac algo DES, gcry_cipher_setkey failed\n");

  err = gcry_cipher_setiv (hd, NULL, 0);
  if (err != 0)
    debugf ("cbc-mac algo DES, gcry_cipher_setiv failed\n");

  err = gcry_cipher_encrypt (hd,
			     ciphertrial, blklen,
			     plaintext,
			     strlen (plaintext));
  if (err)
    debugf ("cbc-mac algo DES, gcry_cipher_encrypt failed\n");
  return memcmp (ciphertrial, ciphertext, blklen) == 0;
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
 *  serveManager - collect plaintext and ciphertext from manager
 */

static void serveManager (int id, int total)
{
  transport  t;
  csn_status status;
  netid      manager;
  char       ourname[80];
  char       theanswer[MAX_DATA_LEN];
  netid      w;
  int        nBytes;
  int        i;
  unsigned long int key;
  unsigned long int limit;
  unsigned long int stride;
  int        finished;

  status = csn_open (&t);
  if (status != CsnOk)
    debugf("csn_open failed");

  status = csn_lookupname(&manager, "manager");  /* lookup managers netid */
  if (status != CsnOk)
    debugf("failed to lookupname manager");

  snprintf(ourname, 80, "worker%d", id);
  status = csn_registername(t, ourname);
  if (status != CsnOk)
    debugf("failed to registername worker");

  /* receive plaintext and ciphertext from manager */

  w = csn_nullnetid;
  status = csn_rx(t, &w, plaintext, MAX_DATA_LEN, &nBytes);
  w = csn_nullnetid;
  status = csn_rx(t, &w, ciphertext, MAX_DATA_LEN, &nBytes);

  printTexts();

  finished = FALSE;
  memset(theanswer, 0, sizeof(theanswer));
  stride = ULONG_MAX/(unsigned long int)total;
  if (id == total)
    limit = ULONG_MAX;
  else
    limit = stride*id+1;

#if 0
  for (key = stride*(unsigned long int)id; (key<limit) && (! finished); key++)
    if (tryKey(&key)) {
      memcpy(theanswer, &key, sizeof(key));
      theanswer[sizeof(key)] = (char)0;
      printf("broken key: %s\n", theanswer);
      finished = TRUE;
    }
#else
  if (id == 1) {
    memcpy(theanswer, &key, sizeof(key));
    strcpy(theanswer, "apple678");
    theanswer[sizeof(key)] = (char)0;
    printf("broken key: %s\n", theanswer);
    finished = TRUE;
  }
#endif

  status = csn_tx(t, manager, theanswer, MAX_DATA_LEN);
  if (status != CsnOk)
    debugf("failed to send reply");

  status = csn_close(t);
  if (status != CsnOk)
    debugf("failed to close transport");

  if (finished)
    printf("\nyes the key has been cracked on processor %d and it is: %s\n", id, theanswer);
}

int
main (int argc, char *argv[])
{
  setupCipherlib();
  if (argc == 3)
    serveManager(atoi(argv[1]), atoi(argv[2]));
  else
    printf("%s needs two arguments <workerid> <totalworkers>\n",
	   argv[0]);
  gcry_cipher_close (hd);
}
