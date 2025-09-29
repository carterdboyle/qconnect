#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <oqs/oqs.h>
#include <openssl/sha.h>

#ifdef __cplusplus
extern "C" {
#endif

static void memzero(void *p, size_t n) {
  volatile unsigned char *vp = (volatile unsigned char *)p;
  while (n--) *vp++ = 0;
}

// Runtime selector
static OQS_KEM *kem_new_runtime() {
  const char *cands[] = { "ML-KEM-512", "Kyber512", "Kyber-512" };
  for (size_t i=0; i < sizeof(cands)/sizeof(cands[0]); i++) {
    OQS_KEM *kem = OQS_KEM_new(cands[i]);
    if (kem) return kem;
  }
  return NULL;
}

static OQS_SIG *sig_new_runtime() {
  const char *cands[] = { "ML-DSA-44", "Dilithium2", "Dilithium-2" };
  for (size_t i=0; i < sizeof(cands) / sizeof(cands[0]); i++) {
    OQS_SIG *sig = OQS_SIG_new(cands[i]);
    if (sig) return sig;
  }
  return NULL;
}

// KEYPAIR generation for testing only 
int pqsig2_keypair(uint8_t *pk_out, uint8_t *sk_out) {
  OQS_SIG *sig = sig_new_runtime();
  if (!sig) return 1;
  int rc = OQS_SIG_keypair(sig, pk_out, sk_out);
  OQS_SIG_free(sig);
  return rc;
}

int pqkem512_keypair(uint8_t *pk_out, uint8_t *sk_out) {
  OQS_KEM *kem = kem_new_runtime();
  if (!kem) return 1;
  int rc = OQS_KEM_keypair(kem, pk_out, sk_out);
  OQS_KEM_free(kem);
  return rc;
}

// ================== KEM (Kyber 512) ======================= //

int pqkem512_name(char *out, size_t out_len) {
  if (!out || out_len == 0) return 2;
  OQS_KEM *kem = kem_new_runtime();
  if (!kem) return 1;
  const char *name = kem->method_name ? kem->method_name : "unknown";
  size_t n = strlen(name);
  if (n >= out_len) n = out_len - 1;
  memcpy(out, name, n);
  out[n] = '\0';
  OQS_KEM_free(kem);
  return 0;
}

int pqkem512_pk_len() {
  OQS_KEM *kem = kem_new_runtime();
  if (!kem) return -1;
  int len = (int)kem->length_public_key;
  OQS_KEM_free(kem);
  return len;
}

int pqkem512_sk_len() {
  OQS_KEM *kem = kem_new_runtime();
  if (!kem) return -1;
  int len = (int)kem->length_secret_key;
  OQS_KEM_free(kem);
  return len;
}

int pqkem512_ct_len() {
  OQS_KEM *kem = kem_new_runtime();
  if (!kem) return -1;
  int len = (int)kem->length_ciphertext;
  OQS_KEM_free(kem);
  return len;
}

int pqkem512_k_len() { return 16; }

// Encapsulate to pk, derive K = SHA256(ss)[0..15]
int pqkem512_encaps_and_k(const uint8_t *pk,
                          uint8_t *ct_out,
                          uint8_t *k_out,
                          size_t k_out_len) {
  if (k_out_len < 16) return 2;

  int rc = 1;
  OQS_KEM *kem = kem_new_runtime();
  if (!kem) return rc;

  uint8_t *ss = (uint8_t *)malloc(kem->length_shared_secret);
  if (!ss) { OQS_KEM_free(kem); return rc; }

  rc = kem->encaps(ct_out, ss, pk);
  if (rc == OQS_SUCCESS) {
    uint8_t digest[SHA256_DIGEST_LENGTH];
    SHA256(ss, kem->length_shared_secret, digest);
    memcpy(k_out, digest, 16);
    memzero(digest, sizeof(digest));
    rc = 0;
  } else {
    rc = 1;
  }

  memzero(ss, kem->length_shared_secret);
  free(ss);
  OQS_KEM_free(kem);
  return rc;
}

// Decaps for testing
int pqkem512_decaps_and_k(const uint8_t *sk, const uint8_t *ct, uint8_t *k_out, size_t k_out_len) {
  if (k_out_len < 16) return 2;

  int rc = -1;
  OQS_KEM *kem = kem_new_runtime();
  if (!kem) return rc;

  uint8_t *ss = (uint8_t*)malloc(kem->length_shared_secret);
  if (!ss) { OQS_KEM_free(kem); return rc; }

  rc = kem->decaps(ss, ct, sk);
  if (rc == OQS_SUCCESS) {
    uint8_t digest[SHA256_DIGEST_LENGTH];
    SHA256(ss, kem->length_shared_secret, digest);
    memcpy(k_out, digest, 16);
    memzero(digest, sizeof(digest));
    rc = 0;
  } else {
    rc = 1;
  }

  memzero(ss, kem->length_shared_secret);
  free(ss);
  OQS_KEM_free(kem);
  return rc;
}

// ================== Dilithium2 (verify) ======================= //
int pqsig2_pk_len() {
  OQS_SIG *sig = sig_new_runtime();
  if (!sig) return -1;
  int len = (int)sig->length_public_key;
  OQS_SIG_free(sig);
  return len;
}

int pqsig2_sk_len() {
  OQS_SIG *sig = sig_new_runtime();
  if (!sig) return -1;
  int len = (int)sig->length_secret_key;
  OQS_SIG_free(sig);
  return len;
}

int pqsig2_sig_max_len() {
  OQS_SIG *sig = sig_new_runtime();
  if (!sig) return -1;
  int len = (int)sig->length_signature;
  OQS_SIG_free(sig);
  return len;
}

// Returns 0 if valid, non-zero otherwise
int pqsig2_sign(uint8_t* sig_out, size_t *sig_len, const uint8_t *m, size_t m_len, const uint8_t *sk) {
  int rc = 1;
  OQS_SIG *sig = sig_new_runtime();
  if (!sig) return rc;
  rc = sig->sign(sig_out, sig_len, m, m_len, sk);
  OQS_SIG_free(sig);
  return rc;
}

// Returns 0 if valid, non-zero otherwise
int pqsig2_verify(const uint8_t *pk, 
                  const uint8_t *m, size_t m_len,
                  const uint8_t *sig_in, size_t sig_len) {
  int rc = 1;
  OQS_SIG *sig = sig_new_runtime();
  if (!sig) return rc;
  rc = sig->verify(m, m_len, sig_in, sig_len, pk);
  OQS_SIG_free(sig);
  return rc;
}


#ifdef __cplusplus
} //extern "C"
#endif