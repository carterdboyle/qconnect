import { webcrypto } from "node:crypto";
import v8 from 'node:v8';
import { TextEncoder, TextDecoder } from "node:util";

// structuredClone from environments that don't expose it in the sandbox
if (typeof globalThis.structuredClone !== 'function') {
  const clone = (val) => v8.deserialize(v8.serialize(val));
  globalThis.structuredClone = clone;
  // also put it on globals JSDOM uses
  if (typeof global !== 'undefined') global.structuredClone = clone;
  if (typeof window !== 'undefined') window.structuredClone = clone;
}

if (!globalThis.TextEncoder) globalThis.TextEncoder = TextEncoder;
if (!globalThis.TextDecoder) globalThis.TextDecoder = TextDecoder;

if (!globalThis.crypto) globalThis.crypto = webcrypto;