#ifndef CRYPT_BLOWFISH_H
#define CRYPT_BLOWFISH_H

/*
 * Minimal bcrypt implementation — no dynamic allocation.
 * Output is always exactly 60 bytes + NUL.
 */

#include <stddef.h>

#define BCRYPT_HASHSIZE 61

/* Hash a password with bcrypt (cost=10, random salt).
 * hash_out must be at least BCRYPT_HASHSIZE bytes.
 * Returns 0 on success, -1 on error. */
int crypt_hashpw(const char *password, char *hash_out, size_t hash_out_size);

/* Check password against a bcrypt hash string.
 * Returns 1 if match, 0 if no match or error. */
int crypt_checkpw(const char *password, const char *hash);

#endif /* CRYPT_BLOWFISH_H */
