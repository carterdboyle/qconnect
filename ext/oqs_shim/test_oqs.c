#include <stdio.h>
#include <stdlib.h>
#include <oqs/oqs.h>

int main() { 
  OQS_KEM *kem = OQS_KEM_new("ML-KEM-512");
  if (!kem) kem = OQS_KEM_new("Kyber512");
  printf("kem? %s\n", kem ? "yes" : "no");
  if (kem) {
    printf("pk=%zu ct=%zu ss=%zu\n", kem->length_public_key, kem->length_ciphertext, kem->length_shared_secret);
    OQS_KEM_free(kem);
  }
  OQS_SIG *sig = OQS_SIG_new("ML-DSA-44");
  if (!sig) sig = OQS_SIG_new("Dilithium2");
  printf("sig? %s\n", sig ? "yes" : "no");
  if (sig) { printf("pk=%zu sig=%zu\n", sig->length_public_key, sig->length_signature); OQS_SIG_free(sig); }
  return 0;
}