// app/javascript/terminal.js

import {
  initOQS,
  diliKeypair,   // [PS, SS]
  kyberKeypair,  // [PK, SK]
  diliSign,      // (SS, M) -> S
  diliVerify,
  kyberDecaps,   // (SK, CT) -> sharedSecret
  kyberEncaps,   // (PK) -> (CT, K)
  deriveKPrimeFromSS // (sharedSecret) -> 16-byte Uint8Array
} from "/pq/oqsClient.js";

// ---------- Base64url helpers ----------
const b64u  = (u8) => btoa(String.fromCharCode(...u8)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
const unb64 = (s) => { s=s.replace(/-/g,'+').replace(/_/g,'/'); const pad=s.length%4===2?'==':s.length%4===3?'=':''; const bin=atob(s+pad); return Uint8Array.from(bin,c=>c.charCodeAt(0)); };

// ---------- IndexedDB ----------
const DB_NAME = "qconnect";
const STORE_KEYS = "keys";
const STORE_CONTACTS = "contacts";

function openDB() {
  return new Promise((res, rej) => {
    const r = indexedDB.open(DB_NAME, 3);
    r.onupgradeneeded = () => {
      const db = r.result;
      if (!db.objectStoreNames.contains(STORE_KEYS))
        db.createObjectStore(STORE_KEYS, { keyPath: "handle" });

      // composite key
      if (db.objectStoreNames.contains(STORE_CONTACTS)) {
        db.deleteObjectStore(STORE_CONTACTS);
      }
      const s = db.createObjectStore(STORE_CONTACTS, { keyPath: ["owner", "handle"] });
      s.createIndex("by_owner", "owner", { unique: false });
      s.createIndex("by_owner_handle", ["owner", "handle"], { unique: true });
    };
    r.onsuccess = () => res(r.result);
    r.onerror   = () => rej(r.error);
  });
}
async function saveKeys(rec) {
  const db = await openDB();
  await new Promise((res, rej) => {
    const tx = db.transaction(STORE_KEYS, "readwrite");
    tx.oncomplete = () => res();
    tx.onerror    = () => rej(tx.error);
    tx.objectStore(STORE_KEYS).put(rec);
  });
}
async function loadKeys(handle) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const tx = db.transaction(STORE_KEYS, "readonly");
    const rq = tx.objectStore(STORE_KEYS).get(handle);
    rq.onsuccess = () => res(rq.result || null);
    rq.onerror   = () => rej(rq.error);
  });
}
async function wipeKeys(handle) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const tx = db.transaction(STORE_KEYS, "readwrite");
    tx.oncomplete = () => res();
    tx.onerror    = () => rej(tx.error);
    tx.objectStore(STORE_KEYS).delete(handle);
  });
}

async function saveContact(owner, rec) {
  const db = await openDB();
  await new Promise((res, rej) => {
    const tx = db.transaction(STORE_CONTACTS, "readwrite");
    tx.oncomplete = () => res();
    tx.onerror = () => rej(tx.error);
    tx.objectStore(STORE_CONTACTS).put({
      owner,
      handle: rec.handle,
      user_id: rec.user_id,
      ps_b64: rec.ps_b64,
      pk_b64: rec.pk_b64,
      alias: rec.alias || null,
      added_at: rec.added_at || Date.now()
    });
  });
}

async function clearContactsFor(owner) {
  const db = await openDB();
  await new Promise((res, rej) => {
    const tx = db.transaction(STORE_CONTACTS, "readwrite");
    const idx = tx.objectStore(STORE_CONTACTS).index("by_owner");
    const range = IDBKeyRange.only(owner);
    idx.openKeyCursor(range).onsuccess = (e) => {
      const cur = e.target.result;
      if (cur) {
        tx.objectStore(STORE_CONTACTS).delete(cur.primaryKey);
        cur.continue();
      }
    };
    tx.oncomplete = () => res();
    tx.onerror = () => rej(tx.error);
  })
}

async function getContactFor(owner, handle) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const tx = db.transaction(STORE_CONTACTS, "readonly");
    const rq = tx.objectStore(STORE_CONTACTS).get(`[${owner},${handle}]`);
    rq.onsuccess = () => res(rq.result || null);
    rq.onerror = () => rej(rq.error);
  });
}

async function listContactsLocal(owner) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const tx = db.transaction(STORE_CONTACTS, "readonly");
    const idx = tx.objectStore(STORE_CONTACTS).index("by_owner");
    const out = [];
    idx.openCursor(IDBKeyRange.only(owner)).onsuccess = (e) => {
      const cur = e.target.result;
      if (cur) { out.push(cur.value); cur.continue(); }
    }
    tx.oncomplete = () => res(out);
    tx.onerror = () => rej(tx.error);
  })
}

// Session and browser helpers
let CSRF = document.querySelector('meta[name="csrf-token"]')?.content || null;

async function refreshCsrf() {
  const r = await fetch('/v1/csrf', { credentials: 'same-origin' });
  if (!r.ok) throw new Error('csrf ' + r.status);
  const { csrf } = await r.json();
  CSRF = csrf;
  const m = document.querySelector('meta[name="csrf-token"]');
  if (m) m.content = csrf;
  return csrf;
}

function xfetch(url, opts ={}) {
  const headers = { 'Content-Type': 'application/json', ...(opts.headers||{})};
  if (CSRF) headers['X-CSRF-Token'] = CSRF;
  return fetch(url, { credentials: 'same-origin', ...opts, headers });
}

async function isAuthenticated() {
  try {
    const session_res = await xfetch('/v1/session');
    const session = await session_res.json();
    if (!session.user_id || !session.handle ) {
      print("user unauthenticated", "err");
      return false;
    }
  }
  catch (e) {
    print("Authentication: " + e.message, "err");
    return false;
  }

  return true;
}

// List contacts (server), cache to IndexedDB, then show cached view
async function syncContacts(owner) {
  const r = await xfetch("/v1/contacts");
  if (!r.ok) throw new Error("HTTP " + r.status);
  const arr = await r.json();

  await clearContactsFor(owner);
  for (const c of arr) await saveContact(owner, c);
}

// Helpers for data structures
function be64(n) { // 8-byte big-endian
  const b = new Uint8Array(8);
  const dv = new DataView(b.buffer);
  dv.setBigUint64(0, BigInt(n), false);
  return b;
}

function concatU8(...parts) {
  const len = parts.reduce((a, p) => a + p.length, 0);
  const out = new Uint8Array(len);
  let o=0; for (const p of parts){ out.set(p,o); o+=p.length; }
  return out;
}

function randBytes(n) {
  const u = new Uint8Array(n);
  crypto.getRandomValues(u);
  return u;
}
function packContactMsg(t_ms, nonce16, peerPS) {
  return concatU8(be64(t_ms), nonce16, peerPS);
}

function packMsgBytes(t_ms, n16, ck, cm) {
  return concatU8(be64(t_ms), n16, ck, cm);
}

// ---------- Crypto helpers ---------------------
async function sha256(u8) {
  const h = await crypto.subtle.digest("SHA-256", u8);
  return new Uint8Array(h);
}

async function importAesKey(raw32) {
  return crypto.subtle.importKey("raw", raw32, "AES-GCM", false, ["encrypt", "decrypt"])
}

async function aesGcmEncrypt(key, iv12, plaintextU8) {
  const ct = await crypto.subtle.encrypt({name: "AES-GCM", iv: iv12}, key, plaintextU8);
  return new Uint8Array(ct);
}

async function aesGcmDecrypt(key, iv12, ctU8) {
  const pt = await crypto.subtle.decrypt({name: "AES-GCM", iv: iv12}, key, ctU8);
  return new Uint8Array(pt);
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

async function listMessages(box) {
  if (!state.handle) return print('set a handle first', 'err');
  const me = await loadKeys(state.handle);
  if (!me) return print('no local keys', 'err');

  const authenticated = await isAuthenticated();
  if (!authenticated) return;

  try {
    const r = await xfetch(`/v1/messages?box=${box||'inbox'}`);
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const arr = await r.json();
    if (!arr.length) return print(`no ${box||'inbox'} messages`, 'muted');

    for (const m of arr) {
      // Verify signature and decrypt when I'm recipient
      const n = unb64(m.n_b64);
      const ck = unb64(m.ck_b64);
      const cm = unb64(m.cm_b64);
      const s = unb64(m.s_b64);
      const msgBytes = packMsgBytes(m.t, n, ck, cm);

      // Verify with sender PS (from contact or server)
      let senderPsB64;
      const cached = await getContactFor?.(state.handle, m.from);
      if (cached?.ps_b64) senderPsB64 = cached.ps_b64;
      else {
        const rs = await xfetch(`/v1/contacts/${encodeURIComponent(m.from)}`);
        if (rs.ok) senderPsB64 = (await rs.json()).ps_b64;
      }
      const PS_sender = senderPsB64 ? unb64(senderPsB64) : null;
      if (PS_sender) {
        const ok = await diliVerify?.(PS_sender, s, msgBytes);
        if (ok !== true) { print(`✖ bad signature from @${m.from}`, 'err'); continue; }
      }

      let preview = '';
      if ((box || 'inbox') === 'inbox') {
        const SK = unb64(me.SK_b64);
        const K = await kyberDecaps(SK, ck);
        const k_kem = (K.length === 32) ? K : await sha256(K);
        const k = await importAesKey(k_kem);

        try {
          const pt = await aesGcmDecrypt(k, n.slice(0,12), cm);
          preview = new TextDecoder().decode(pt);
        } catch {
          preview = '[decrypt failed]';
        }
      } else {
        preview = ['[outgoing ciphertext]'];
      }

      print(`#${m.id} ${new Date(m.t).toISOString()} @${m.from} -> @${m.to}: ${preview}`);
    }
  } catch (e) {
    print('messages error: ' + e.message, 'err');
  }
}

const commands = {
  help() {
    print("COMMANDS:", "muted");
    print("  handle <name>              # set active handle");
    print("  status                     # show local key status");
    print("KEY MANAGEMENT:", "muted")
    print("  genkeys                    # generate keys and store in IndexedDB");
    print("  show ps|pk                 # print your public keys");
    print("  wipe                       # delete keys for active handle");
    print("AUTHENTICATION:", "muted")
    print("  register                   # run server registration flow");
    print("  login                      # run server login flow");
    print("CONTACTS:", "muted")
    print("  request <handle> [note...] # send a contact request to user")
    print("  requests                   # view pending contact requests")
    print("  accept <request_id>        # accept a request from a given contact")
    print("  decline <request_id>       # decline a request from a given contact")
    print("  contacts                   # view contact book")
    print("  clear                      # clear screen");
    print("MESSAGING:", "muted")
    print("  send <handle> <message...> # send a user a message");
    print("  outbox                     # view outgoing messages");
    print("  inbox                      # view incoming messages");
  },

  async handle(args) {
    const next = args[0];
    if (!args[0]) return print("usage: handle <name>", "err");

    if (state.handle && state.handle !== next) {
      // clear server session so subsequent calls are unauthenticated
      try {
        await xfetch("/v1/session", { method: "DELETE" });
        await refreshCsrf();
        print("SERVER SESSION CLEARED", "muted");
      }
      catch(_) { /* ignore */ }
    }
    state.handle = next;
    print("handle set -> " + state.handle, "ok");
    print('RUN "LOGIN" TO AUTHENTICATE THIS HANDLE', "muted");
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
      const r1 = await xfetch("/v1/register/init", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          handle: state.handle,
          ps_b64: rec.PS_b64,
          pk_b64: rec.PK_b64
        })
      });
      if (!r1.ok) throw new Error("init " + r1.status);
      const { m_b64, ct_b64, nonce } = await r1.json();

      // 2) compute S and K'
      const SS = unb64(rec.SS_b64);
      const SK = unb64(rec.SK_b64);
      const M  = unb64(m_b64);
      const CT = unb64(ct_b64);

      const S      = await signMSG(SS, M);
      const ss_raw = await decaps(SK, CT);
      const Kp16   = await deriveKPrimeFromSS(ss_raw); // SHA-256 -> first 16 bytes

      // 3) reply with signature + K' (16 bytes)
      const r2 = await xfetch("/v1/register/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          handle:  state.handle,
          sig_b64: b64u(S),
          kp_b64:  b64u(Kp16),
          nonce: nonce
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
      const r1 = await xfetch("/v1/login/challenge", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ handle: state.handle })
      });
      if (!r1.ok) throw new Error("challenge " + r1.status);
      const { challenge_b64, nonce } = await r1.json();

      // 2) sign the challenge with SS (Dilithium)
      const SS = unb64(rec.SS_b64);
      const M  = unb64(challenge_b64);
      const S  = await signMSG(SS, M);

      // 3) send signature back; server retrieves handle & challenge from session
      const r2 = await xfetch("/v1/login/submit", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ signature_b64: b64u(S), nonce: nonce })
      });
      if (!r2.ok) throw new Error("submit " + r2.status);
      const done = await r2.json();

      if (done.ok) print(`logged in sucessfully ✔ (id=${done.user_id})`, "ok");
      else         print(`login failed X: ${JSON.stringify(done.message)}`, "err");
    } catch (e) {
      print("login error: " + e.message, "err");
    }
  },

  async request(args) {
    const to = args[0];
    if (!to) return print("usage: request <handle> [note...]", "err");
    const note = args.slice(1).join(" ");

    if (!state.handle) return print("set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (!rec) return print("no keys; run genkeys", "err");

    const authenticated = await isAuthenticated();
    if (!authenticated) return;

    try {
      const rShow = await xfetch(`/v1/contacts/${encodeURIComponent(to)}`);
      if (rShow.status === 404) return print("no such user", "err");
      if (!rShow.ok) throw new Error("lookup " + rShow.status);
      
      const { ps_b64, contact: is_contact } = await rShow.json();
      if (is_contact) return print("Requestee is already a contact!", "err");
      const PS_peer = unb64(ps_b64);

      // Build tuple
      const t = Date.now();
      const n = randBytes(16);

      const SS = unb64(rec.SS_b64);
      const M = packContactMsg(t, n, PS_peer);
      const S = await signMSG(SS, M);

      const r = await xfetch("/v1/contacts/requests", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          handle: to,
          note,
          t,
          n_b64: b64u(n),
          s_b64: b64u(S),
          ps_peer_b64: b64u(PS_peer)
        })
      });

      if (!r.ok) throw new Error("HTTP " + r.status);
      
      const js = await r.json();
      print(`request send -> id=${js.id} to=${js.recipient_handle}`, "ok");
    } 
    catch (e) { 
      print("request error: " + e.message, "err"); 
    }
  },

  async requests() {
    if (!state.handle) return print("set a handle first", "err");

    const authenticated = await isAuthenticated();
    if (!authenticated) return;

    try {
      const r = await xfetch("/v1/contacts/requests");
      if (!r.ok) throw new Error("HTTP " + r.status);
      const arr = await r.json();
      if (!arr.length) return print("no pending requests", "muted");
      arr.forEach(it => print(`id=${it.id} from=${it.from} note="${it.note||""}" at=${it.at}`));
    } catch (e) { print("requests error: " + e.message, "err"); }
  },

  async accept(args) {
    const id = args[0];
    if (!id) return print("usage: accept <request_id>", "err");
    if (!state.handle) return print("set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (!rec) return print("no keys; run genkeys","err");

    const authenticated = await isAuthenticated();
    if (!authenticated) return;

    try {
      const rs = await xfetch("/v1/contacts/requests");
      const list = await rs.json();
      const row = list.find(r => String(r.id) === String(id));
      if (!row) return print("unknown request id", "err");


      const rShow = await xfetch(`/v1/contacts/${encodeURIComponent(row.from)}`)
      if (!rShow.ok) throw new Error("lookup " + rShow.status);
      const { ps_b64: from_ps_b64, contact: is_contact } = await rShow.json();
      if (is_contact) return print("Requestee is already a contact!", "err");

      const PS_requester = unb64(from_ps_b64);

      const t = Date.now();
      const n = randBytes(16);
      const SS = unb64(rec.SS_b64);
      const M2 = packContactMsg(t, n, PS_requester);
      const S2 = await signMSG(SS, M2);

      const r = await xfetch(`/v1/contacts/requests/${id}/respond`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ decision: "accept", t, n_b64: b64u(n), s_b64: b64u(S2) })
      });
      if (!r.ok) throw new Error("HTTP " + r.status);
      const js = await r.json();
      print(`accepted -> status=${js.status}`, "ok");

      // pull fresh contacts from server
      await syncContacts(state.handle);
    }
    catch (e) {
      print("accept error: " + e.message, "err");
    }
  },

  async decline(args) {
    const id = args[0];
    if (!id) return print("usage: decline <request_id>", "err");
    if (!state.handle) return print("set a handle first", "err");

    const authenticated = await isAuthenticated();
    if (!authenticated) return;

    try {
      const r = await xfetch(`/v1/contacts/requests/${id}/respond`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ decision: "decline" })
      });
      if (!r.ok) throw new Error("HTTP " + r.status);
      const js = await r.json();
      print(`declined -> status=${js.status}`, "ok");
    }
    catch (e) {
      print("decline error: " + e.message, "err");
    }
  },

  async contacts() {
    if (!state.handle) return print("set a handle first", "err");

    const authenticated = await isAuthenticated();
    if (!authenticated) return; 

    try {
      await syncContacts(state.handle);
      const list = await listContactsLocal(state.handle);
      if (!list.length) return print("no contacts", "muted");
      list.forEach(c => {
        print(`@${c.handle}  (id=${c.user_id})`);
      });
    }
    catch (e) {
      print("contacts error: " + e.message, "err");
    }
  },

  async send(args) {
    const to = args[0];
    const text = args.slice(1).join(" ");
    if (!to || !text) return print("usage: send <handle> <message...>", "err");
    if (!state.handle) return print('set a handle first', 'err');
    const me = await loadKeys(state.handle); if (!me) return print('no local keys', 'err');

    const authenticated = await isAuthenticated();
    if (!authenticated) return;

    try {
      // 1) Get recipients PK
      // try local first, then hit the server
      let rec = await getContactFor?.(state.handle, to);
      if (!rec) {
        const r = await xfetch(`/v1/contacts/${encodeURIComponent(to)}`);
        if (!r.ok) throw new Error('lookup ' + r.status);
        rec = await r.json();
      }
      const PK_peer = unb64(rec.pk_b64);

      // 2) KEM encaps CK
      await initOQS?.();
      const { ct: CK, k } = await kyberEncaps(PK_peer);

      // 3) Encrypt with AES-GCM(iv = n[0..11])
      const K = (k.length === 32) ? k : await sha256(k);

      const iv = randBytes(16);
      const iv12 = iv.slice(0, 12);
      const key = await importAesKey(K);
      const CM = await aesGcmEncrypt(key, iv12, new TextEncoder().encode(text));

      // 4) sign (T || n || CK || CM)
      const t = Date.now();
      const M = packMsgBytes(t, iv, CK, CM);
      const SS = unb64(me.SS_b64);
      const S = await diliSign(SS, M);

      // 5) POST /v1/messages
      const r2 = await xfetch('/v1/messages', {
        method: 'POST',
        body: JSON.stringify({
          to_handle: to,
          t,
          n_b64: b64u(iv),
          ck_b64: b64u(CK),
          cm_b64: b64u(CM),
          s_b64: b64u(S)
        })
      });
      if (!r2.ok) throw new Error('HTTP ' + r2.status);
      const js = await r2.json();
      print(`sent -> id=${js.id} to=@${to}`, 'ok');
    }
    catch (e) {
      print('send error: ' + e.message, 'err');
    }
  },

  async inbox() {
    await listMessages('inbox');
  },

  async outbox() {
    await listMessages('outbox');
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
