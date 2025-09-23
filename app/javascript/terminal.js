// app/javascript/terminal.js

import {
  initOQS,
  diliKeypair,   // [PS, SS]
  kyberKeypair,  // [PK, SK]
  diliSign,      // (SS, M) -> S
  kyberDecaps,   // (SK, CT) -> sharedSecret
  deriveKPrimeFromSS // (sharedSecret) -> 16-byte Uint8Array
} from "/pq/oqsClient.js";

// ---------- Base64url helpers ----------
const b64u  = (u8) => btoa(String.fromCharCode(...u8)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
const unb64 = (s) => { s=s.replace(/-/g,'+').replace(/_/g,'/'); const pad=s.length%4===2?'==':s.length%4===3?'=':''; const bin=atob(s+pad); return Uint8Array.from(bin,c=>c.charCodeAt(0)); };

// ---------- IndexedDB ----------
const DB_NAME = "qpigeon", STORE = "keys";
function openDB() {
  return new Promise((res, rej) => {
    const r = indexedDB.open(DB_NAME, 1);
    r.onupgradeneeded = () => {
      const db = r.result;
      if (!db.objectStoreNames.contains(STORE))
        db.createObjectStore(STORE, { keyPath: "handle" });
    };
    r.onsuccess = () => res(r.result);
    r.onerror   = () => rej(r.error);
  });
}
async function saveKeys(rec) {
  const db = await openDB();
  await new Promise((res, rej) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.oncomplete = () => res();
    tx.onerror    = () => rej(tx.error);
    tx.objectStore(STORE).put(rec);
  });
}
async function loadKeys(handle) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const tx = db.transaction(STORE, "readonly");
    const rq = tx.objectStore(STORE).get(handle);
    rq.onsuccess = () => res(rq.result || null);
    rq.onerror   = () => rej(rq.error);
  });
}
async function wipeKeys(handle) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.oncomplete = () => res();
    tx.onerror    = () => rej(tx.error);
    tx.objectStore(STORE).delete(handle);
  });
}

// ---------- OQS via your oqsClient.js ----------
async function genKeypairs() {
  await initOQS();
  const [PS, SS] = await diliKeypair();   // ML-DSA-44
  const [PK, SK] = await kyberKeypair();  // ML-KEM-512
  return { PS, SS, PK, SK };
}
async function signMSG(SS, M) { await initOQS(); return await diliSign(SS, M); }
async function decaps(SK, C)  { await initOQS(); return await kyberDecaps(SK, C); }

// ---------- Terminal UI ----------
const term  = document.getElementById("terminal");
const input = document.getElementById("input");

function print(t, c = "") {
  const d = document.createElement("div");
  d.className = "line " + c;
  d.textContent = t;
  term.appendChild(d);
  term.scrollTop = term.scrollHeight;
}
function printHTML(h) {
  const d = document.createElement("div");
  d.className = "line";
  d.innerHTML = h;
  term.appendChild(d);
  term.scrollTop = term.scrollHeight;
}
function banner() {
  print("=== QCONNECT SECURE CONSOLE ===");
  print("Algorithms: ML-DSA-44 (sign), ML-KEM-512 (KEM)");
  print('Type "help" for commands.');
}

let state = { handle: null };

const commands = {
  help() {
    print("COMMANDS:", "muted");
    print("  handle <name>     # set active handle");
    print("  status            # show local key status");
    print("  genkeys           # generate keys and store in IndexedDB");
    print("  show ps|pk        # print your public keys");
    print("  register          # run server registration flow");
    print("  login             # run server login flow");
    print("  wipe              # delete keys for active handle");
    print("  clear             # clear screen");
  },

  handle(args) {
    if (!args[0]) return print("usage: handle <name>", "err");
    state.handle = args[0];
    print("handle set -> " + state.handle, "ok");
  },

  async status() {
    if (!state.handle) return print("set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (rec) print(`keys present for ${state.handle} [created ${new Date(rec.createdAt).toISOString()}]`, "ok");
    else     print(`no keys for ${state.handle}`, "err");
  },

  async genkeys() {
    if (!state.handle) return print("set a handle first", "err");
    try {
      const { PS, SS, PK, SK } = await genKeypairs();
      await saveKeys({
        handle: state.handle,
        PS_b64: b64u(PS), SS_b64: b64u(SS),
        PK_b64: b64u(PK), SK_b64: b64u(SK),
        createdAt: Date.now()
      });
      print("generated ML-DSA-44 + ML-KEM-512 keys", "ok");
    } catch (e) {
      print("keygen failed: " + e.message, "err");
    }
  },

  async show(args) {
    if (!state.handle) return print("set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (!rec) return print("no keys; run genkeys", "err");
    const what = args[0];
    if      (what === "ps") print(rec.PS_b64);
    else if (what === "pk") print(rec.PK_b64);
    else                    print("usage: show ps|pk", "err");
  },

  async wipe() {
    if (!state.handle) return print("set a handle first", "err");
    await wipeKeys(state.handle);
    print("keys wiped for " + state.handle, "ok");
  },

  clear() {
    term.innerHTML = "";
    banner();
  },

  async register() {
    if (!state.handle) return print("set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (!rec) return print("no keys; run genkeys", "err");

    try {
      // 1) send public keys
      const r1 = await fetch("/v1/register/init", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          handle: state.handle,
          ps_b64: rec.PS_b64,
          pk_b64: rec.PK_b64
        })
      });
      if (!r1.ok) throw new Error("init " + r1.status);
      const { m_b64, ct_b64 } = await r1.json();

      // 2) compute S and K'
      const SS = unb64(rec.SS_b64);
      const SK = unb64(rec.SK_b64);
      const M  = unb64(m_b64);
      const CT = unb64(ct_b64);

      const S      = await signMSG(SS, M);
      const ss_raw = await decaps(SK, CT);
      const Kp16   = await deriveKPrimeFromSS(ss_raw); // SHA-256 -> first 16 bytes

      // 3) reply with signature + K' (16 bytes)
      const r2 = await fetch("/v1/register/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          handle:  state.handle,
          sig_b64: b64u(S),
          kp_b64:  b64u(Kp16)
        })
      });
      if (!r2.ok) throw new Error("verify " + r2.status);
      const done = await r2.json();
      if (done.verified) print("registered ✔ " + JSON.stringify(done), "ok");
      else               print("registration failed: " + JSON.stringify(done), "err");
    } catch (e) {
      print("registration error: " + e.message, "err");
    }
  },

  async login() {
    if (!state.handle) return print("set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (!rec) return print("no keys; run genkeys", "err");

    try {
      // 1) ask server for challenge (stored in session server-side)
      const r1 = await fetch("/v1/login/challenge", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ handle: state.handle })
      });
      if (!r1.ok) throw new Error("challenge " + r1.status);
      const { challenge_b64 } = await r1.json();

      // 2) sign the challenge with SS (Dilithium)
      const SS = unb64(rec.SS_b64);
      const M  = unb64(challenge_b64);
      const S  = await signMSG(SS, M);

      // 3) send signature back; server retrieves handle & challenge from session
      const r2 = await fetch("/v1/login/submit", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ signature_b64: b64u(S) })
      });
      if (!r2.ok) throw new Error("submit " + r2.status);
      const done = await r2.json();

      if (done.ok) print("logged in ✔ user_id=" + done.user_id, "ok");
      else         print("login failed: " + JSON.stringify(done), "err");
    } catch (e) {
      print("login error: " + e.message, "err");
    }
  }
}

// ---------- REPL ----------
input.addEventListener("keydown", async (e) => {
  if (e.key === "Enter") {
    const raw = input.value.trim();
    input.value = "";
    printHTML('<span class="prompt">$</span> ' + raw);
    if (!raw) return;

    const [cmd, ...args] = raw.split(/\s+/);
    const fn = commands[cmd];
    if (fn) await fn(args);
    else    print("unknown command: " + cmd, "err");
  }
});

banner();
setTimeout(() => input.focus(), 50);
