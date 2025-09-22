let mod;
export async function initOQS() {
  if (mod) return mod;
  const factory = (await import("/oqs/oqs.js")).default;

  mod = await factory({ 
    locateFile: (p) => p.endsWith(".wasm") ? "/oqs/oqs.wasm" : p
  });

  return mod;
}

export async function diliKeypair() {
  const M = await initOQS();
  const rc = M.cwrap("dili_keypair", "number", [])();
  if (rc !== 0) throw new Error("dili_keypair failed");
  const pk = new Uint8Array(M.HEAPU8.buffer, M.cwrap("get_dili_pk_ptr", "number", [])(), M.cwrap("get_dili_pk_len", "number", [])());
  const sk = new Uint8Array(M.HEAPU8.buffer, M.cwrap("get_dili_sk_ptr", "number", [])(), M.cwrap("get_dili_sk_len", "number", [])());
  return [pk.slice(0), sk.slice(0)];
}

export async function diliSign(sk, msg) {
  const M = await initOQS();
  const skPtr = M._malloc(sk.length); M.HEAPU8.set(sk, skPtr);
  const msgPtr = M._malloc(msg.length); M.HEAPU8.set(msg, msgPtr);
  const rc = M.cwrap("dili_sign", "number", ["number", "number", "number", "number"])(skPtr, sk.length, msgPtr, msg.length);
  M._free(msgPtr); M._free(skPtr);
  if (rc !== 0) throw new Error("sign failed");
  const sig = new Uint8Array(M.HEAPU8.buffer, M.cwrap("get_dili_sig_ptr", "number", [])(), M.cwrap("get_dili_sig_len", "number", [])());
  return sig.slice(0);
}

export async function kyberKeypair() {
  const M = await initOQS();
  const rc = M.cwrap("kyber_keypair", "number", [])();
  if (rc !== 0) throw new Error("kyber_keypair failed");
  const pk = new Uint8Array(M.HEAPU8.buffer, M.cwrap("get_kyber_pk_ptr", "number", [])(), M.cwrap("get_kyber_pk_len", "number", [])());
  const sk = new Uint8Array(M.HEAPU8.buffer, M.cwrap("get_kyber_sk_ptr", "number", [])(), M.cwrap("get_kyber_sk_len", "number", [])());
  return [pk.slice(0), sk.slice(0)];
}

export async function kyberDecaps(sk, ct) {
  const M = await initOQS();
  const skPtr = M._malloc(sk.length); M.HEAPU8.set(sk, skPtr);
  const ctPtr = M._malloc(ct.length); M.HEAPU8.set(ct, ctPtr);
  const rc = M.cwrap("kyber_decaps", "number", ["number", "number", "number"])(skPtr, sk.length, ctPtr, ct.length);
  M._free(ctPtr); M._free(skPtr);
  if (rc !== 0) throw new Error("decaps failed");
  const k = new Uint8Array(M.HEAPU8.buffer, M.cwrap("get_kyber_k_ptr", "number", [])(), M.cwrap("get_kyber_k_len", "number", [])());
  return k.slice(0);
}