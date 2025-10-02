export async function initOQS() {}
export async function diliKeypair()  { return [new Uint8Array(0), new Uint8Array(0)]; }
export async function kyberKeypair() { return [new Uint8Array(0), new Uint8Array(0)]; }
export async function diliSign()     { return new Uint8Array(64); }
export async function diliVerify()   { return true; }
export async function kyberDecaps()  { return new Uint8Array(32); }
export async function kyberEncaps()  { return { ct: new Uint8Array(32), k: new Uint8Array(32) }; }
export async function deriveKPrimeFromSS() { return new Uint8Array(16); }