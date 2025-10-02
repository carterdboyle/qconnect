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

import { createConsumer } from "@rails/actioncable"
window.Cable = createConsumer();

// ---------- Base64url helpers ----------
const b64u  = (u8) => btoa(String.fromCharCode(...u8)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
const unb64 = (s) => { s=s.replace(/-/g,'+').replace(/_/g,'/'); const pad=s.length%4===2?'==':s.length%4===3?'=':''; const bin=atob(s+pad); return Uint8Array.from(bin,c=>c.charCodeAt(0)); };

// ---------- IndexedDB ----------
const DB_NAME = "qconnect";
const STORE_KEYS = "keys";
const STORE_CONTACTS = "contacts";
const STORE_CONV = "conversations";
const STORE_MSGS = "messages";
const DB_VERSION = 5;

function openDB() {
  return new Promise((res, rej) => {
    const r = indexedDB.open(DB_NAME, DB_VERSION);
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

      if (db.objectStoreNames.contains(STORE_CONV)) db.deleteObjectStore(STORE_CONV);
      const conv = db.createObjectStore(STORE_CONV, { keyPath: ["owner", "peer"]});
      conv.createIndex("by_owner", "owner", { unique: false });

      if (db.objectStoreNames.contains(STORE_MSGS)) db.deleteObjectStore(STORE_MSGS);
      const msgs = db.createObjectStore(STORE_MSGS, { keyPath: ["owner", "peer", "id"] });
      msgs.createIndex("by_owner_peer_time", ["owner", "peer", "t"], { unique: false });
      msgs.createIndex("by_owner_peer_time_id", ["owner", "peer", "t", "id"], { unique: false });

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
    const rq = tx.objectStore(STORE_CONTACTS).get([owner, handle]);
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

async function putConversation(owner, peer, payload) {
  const db = await openDB();
  await new Promise((res, rej) => {
    const tx = db.transaction(STORE_CONV, "readwrite");
    tx.oncomplete = res;
    tx.onerror = () => rej(tx.error);
    tx.objectStore(STORE_CONV).put({ owner, peer, ...payload });
  })
}

async function getConversation(owner, peer) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const tx = db.transaction(STORE_CONV, "readonly");
    const rq = tx.objectStore(STORE_CONV).get([owner, peer]);
    rq.onsuccess = () => res(rq.result || null );
    rq.onerror = () => rej(rq.error);
  });
}

async function upsertPlainMessage(owner, peer, m) {
  // m: { id, t, from, to, text }
  const msg = { ...m };
  const db = await openDB();
  await new Promise((res, rej) => {
    const tx = db.transaction(STORE_MSGS, "readwrite");
    tx.oncomplete = res;
    tx.onerror = () => rej(tx.error);
    tx.objectStore(STORE_MSGS).put({ owner, peer, ...msg});
  })
}

async function listChatLocal(owner, peer, limit=50) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const out = [];
    const tx = db.transaction(STORE_MSGS, "readonly");
    const idx = tx.objectStore(STORE_MSGS).index("by_owner_peer_time_id");
    const range = IDBKeyRange.bound([owner, peer, -Infinity, -Infinity],[owner, peer, Infinity, Infinity]);
    idx.openCursor(range, "next").onsuccess = (e) => {
      const cur = e.target.result;
      if (!cur) return;
      out.push(cur.value);
      if (out.length >= limit) return;
      cur.continue();
    }
    tx.oncomplete = () => res(out);
    tx.onerror = () => rej(tx.error);
  })
}

async function maxLocalCursor(owner, peer) {
  const last = await lastMessageLocal(owner, peer);
  return { t_ms: last?.t ?? 0, id: last?.id ?? 0 };
}

async function getServerLastRead(conversationId) {
  const r = await xfetch(`/v1/chats/${encodeURIComponent(conversationId)}/last_read`);
  if (!r.ok) throw new Error("last_read" + r.status);
  const { last_read_message_id } = await r.json();
  return Number(last_read_message_id) || 0;
}

async function fetchEncryptedSinceTime(conversationId, afterT, afterId, limit=500) {
  const url = `/v1/chats/${encodeURIComponent(conversationId)}/messages?after_t=${encodeURIComponent(afterT)}&after_id=${encodeURIComponent(afterId)}&limit=${encodeURIComponent(limit)}`;
  const r = await xfetch(url);
  if (!r.ok) throw new Error("messages_since " + r.status);
  return await r.json();
}

async function syncNewFromServer(owner, peer, conversationId) {
  const { t_ms, id } = await maxLocalCursor(owner, peer);
  const arr = await fetchEncryptedSinceTime(conversationId, t_ms, id);
  for (const em of arr) {
    const m = await decryptInboundToPlain(owner, em);
    await upsertPlainMessage(owner, peer, m);
  }
  return arr.length;
}

function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

async function _markRead(conversationId, owner, peer) {
  await xfetch(`/v1/chats/${encodeURIComponent(conversationId)}/read`, {
    method: "POST"
  });

  const lastInbound = await lastInboundMessageLocal(owner, peer);
  if (lastInbound) await putConversation(owner, peer, {
    conversation_id: conversationId,
    last_read_id: lastInbound.id
  })
}
const markRead = debounce(_markRead, 250);

async function lastInboundMessageLocal(owner, peer) {
  const m = await lastMessageLocal(owner, peer);
  if (m && m.to === owner) return m;
  const list = await listChatLocal(owner, peer, 200);
  for (let i = list.length - 1; i >= 0; i--) {
    if (list[i].to === owner) return list[i];
  }
  return null;
}

async function lastMessageLocal(owner, peer) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const tx = db.transaction(STORE_MSGS, "readonly");
    const idx = tx.objectStore(STORE_MSGS).index("by_owner_peer_time_id");
    const range = IDBKeyRange.bound([owner, peer, -Infinity, -Infinity], [owner, peer, Infinity, Infinity]);
    const rq = idx.openCursor(range, "prev");
    rq.onsuccess = () => res(rq.result ? rq.result.value : null);
    rq.onerror = () => rej(rq.error);
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
      print('- User unauthenticated. Call "login" cmd', "err");
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

// ---------- Day helpers ------------------------
const dayKey = (t) => {
  const d = new Date(typeof t === 'number' ? t : Number(t));
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
};
const isToday = (t) => dayKey(t) === dayKey(Date.now());
const dayLabel = (t) =>
  new Intl.DateTimeFormat(undefined, { weekday: "short", month: "short", day: "numeric", year: "numeric"})
    .format(new Date(t));

// Remember last printed day for the open chat
function ensureChatStateDay(key) { if (chatState) chatState.lastDayKey = key; }

// print a muted day divider
function printDayDivider(t) {
  print(`—— ${dayLabel(t)} ——`, "muted");
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

async function decryptInboundToPlain(owner, encMsg) {
  // encMsg: { id, from, to, to, n_b64, ck_b64, cm_b64, ... }
  const n = unb64(encMsg.n_b64);
  const ck = unb64(encMsg.ck_b64);
  const cm = unb64(encMsg.cm_b64);

  if (encMsg.to !== owner) {
    return { id: encMsg.id, t: encMsg.t, from: encMsg.from, to: encMsg.to, text: null }
  }

  const rec = await loadKeys(owner);
  if (!rec) throw new Error("no local SK");
  const SK = unb64(rec.SK_b64);

  const K = await kyberDecaps(SK, ck);
  const key = await importAesKey(K);
  const pt = await aesGcmDecrypt(key, n.slice(0,12), cm);
  const text = new TextDecoder().decode(pt);

  return { id: encMsg.id, t: encMsg.t, from: encMsg.from, to: encMsg.to, text };
  
} 

// Initial load: if no plaintext, fetch & decrpyt history once
async function ensureLocalHistory(owner, peer) {
  let local = await listChatLocal(owner, peer, 1);
  if (local.length > 0) return;
  
  local = await listChatLocal(owner, peer, 1e9);

  const r = await xfetch("/v1/chats/open", {
    method: "POST",
    body: JSON.stringify({ handle: peer })
  });

  if (!r.ok) throw new Error(`open ${r.status} (${(await r.json()).message})`);
  const { conversation_id, history } = await r.json();
  await putConversation(owner, peer, { conversation_id, last_read_id: null });

  for (const em of history) {
    const m = await decryptInboundToPlain(owner, em);
    await upsertPlainMessage(owner, peer, m);
  }

  return history.length;
}

// Append new (from Action Cable)
async function appendIncoming(owner, peer, encMsg) {
  const m = await decryptInboundToPlain(owner, encMsg);
  await upsertPlainMessage(owner, peer, m);
}

// Subscribe helper
function subscribeChat(conversation_id, owner, peer) {
  const sub = window.Cable?.subscriptions.create(
    { channel: "ChatChannel", conversation_id },
    {
      received: async (data) => {
        if (data.from === owner) return;

        await appendIncoming(owner, peer, data);
        const last = await lastMessageLocal(owner, peer);
        if (!last) return;
        
        const k = dayKey(last.t);
        if (chatState?.lastDayKey !== k) {
          // only show divider when days change
          printDayDivider(last.t);
          ensureChatStateDay(k);
        }
        
        const time = new Date(data.t).toLocaleTimeString();
        printChat(`${time} @${data.from}`, `${last?.text ?? "[decrypt failed]"}`);

        // Mark as read when receiving
        markRead(conversation_id, owner, peer);
      }
    }
  );
  return sub;
}

async function renderLocalChat(owner, peer, added) {
  const list = await listChatLocal(owner, peer);
  
  let lastKey = null;
  list.forEach((m, i) => {
    const who = (m.from === owner) ? "me" : "@"+m.from;
    const time = new Date(m.t).toLocaleTimeString();
    const text = (m.text ?? "[sent]");
    added && 
      ((list.length - added) == i) &&
      print(`${added} new message${added > 1 ? "s" : ""}!\n`, "ok")
      
    const k = dayKey(m.t);
    if (k !== lastKey) {
      // only show divider if this block isn't today
      printDayDivider(m.t);
      lastKey = k;
    }
    printChat(`${time} ${who}`, text);
  });
  ensureChatStateDay(lastKey);
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
function printChat(preface, txt) {
  const d = document.createElement("div");
  d.className = "line";
  d.innerHTML = `<span class='preface muted'>${preface}: </span><span class="chat">${txt}</span>`;
  term.appendChild(d);
  term.scrollTop = term.scrollHeight;
}
function banner() {
  print("=== QCONNECT SECURE CONSOLE ===");
  print("Algorithms: ML-DSA-44 (sign), ML-KEM-512 (KEM)");
  print('Type "help" for commands.');
}

// States
let state = { handle: null };
let chatState = null;

async function inboxSummary() {
  const r = await xfetch("/v1/chats/summary");
  if (!r.ok) throw new Error("HTTP " + r.status);
  return await r.json(); // [{ handle, undread, last_t, conversation_id }]
}

async function sendMessageAndGetId(to, text) {
  if (!to || !text) throw new Error("Invalid input parameters");
  if (!state.handle) return print('set a handle first', 'err');
  const me = await loadKeys(state.handle); if (!me) return print('no local keys', 'err');

  const authenticated = await isAuthenticated();
  if (!authenticated) return;

  try {
    // 1) Get recipients PK
    // try local first, then hit the server
    let rec = await getContactFor(state.handle, to);
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
    return js.id;
  }
  catch (e) {
    print('send error: ' + e.message, 'err');
  }
}

const commands = {
  help() {
    print("COMMANDS:", "muted");
    print("  handle <name>              # set active handle");
    print("  status                     # show local key status and current handle");
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
    print("  inbox                      # view new messages");
    print("  chat <handle>              # enter a secure chat with user");
  },

  async handle(args) {
    const next = args[0];
    if (!args[0]) return print("- Usage: handle <name>", "err");

    try {
      await xfetch("/v1/session", { method: "DELETE" });
      await refreshCsrf();
      print("- Server session cleared", "ok");
    }
    catch(_) { /* ignore */ }

    state.handle = next;
    print("- Handle set: " + state.handle, "ok");
    print("- Run 'login' to authenticate current handle", "muted");
  },

  async status() {
    if (!state.handle) return print("- Set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (rec) print(`- Keys present for ${state.handle} [created ${new Date(rec.createdAt).toISOString()}]`, "ok");
    else     print(`- No keys for ${state.handle}`, "err");
  },

  async genkeys() {
    if (!state.handle) return print("- Set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (rec) return print("- Keys already exist for this user. Contact administrator to reset keys.", "err");
    try {
      const { PS, SS, PK, SK } = await genKeypairs();
      await saveKeys({
        handle: state.handle,
        PS_b64: b64u(PS), SS_b64: b64u(SS),
        PK_b64: b64u(PK), SK_b64: b64u(SK),
        createdAt: Date.now()
      });
      print("- Generated ML-DSA-44 + ML-KEM-512 keys", "ok");
    } catch (e) {
      print("- Keygen failed: " + e.message, "err");
    }
  },

  async show(args) {
    if (!state.handle) return print("- Set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (!rec) return print("- No keys. Run 'genkeys' cmd", "err");
    const what = args[0];
    if      (what === "ps") print(rec.PS_b64);
    else if (what === "pk") print(rec.PK_b64);
    else                    print("- Usage: show <ps|pk>", "err");
  },

  async wipe() {
    if (!state.handle) return print("- Set a handle first", "err");
    await wipeKeys(state.handle);
    print("- Keys wiped for " + state.handle, "ok");
  },

  clear() {
    term.innerHTML = "";
    banner();
  },

  async register() {
    if (!state.handle) return print("- Set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (!rec) return print("- No keys. Run genkeys", "err");

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
      if (!r1.ok) throw new Error(`init ${r1.status} (${(await r1.json()).message})`);
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
      if (!r2.ok) throw new Error(`verify ${r2.status} (${(await r2.json()).error})`);
      const done = await r2.json();
      if (done.verified) print("- Registered ✔", "ok");
      else               print("- Registration failed: " + JSON.stringify(done.error), "err");
    } catch (e) {
      print("- Registration error: " + e.message, "err");
    }
  },

  async login() {
    if (!state.handle) return print("- Set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (!rec) return print("- No keys. Run genkeys", "err");

    try {
      // 1) ask server for challenge (stored in session server-side)
      const r1 = await xfetch("/v1/login/challenge", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ handle: state.handle })
      });
      if (!r1.ok) throw new Error(`challenge ${r1.status} (${(await r1.json()).message})`);
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
      if (!r2.ok) throw new Error(`submit ${r2.status} (${(await r2.json()).message})`);
      const done = await r2.json();

      if (done.ok) print(`- Logged in sucessfully ✔`, "ok");
      else         print(`- Login failed X: ${JSON.stringify(done.message)}`, "err");
    } catch (e) {
      print("- Login error: " + e.message, "err");
    }
  },

  async request(args) {
    const to = args[0];
    if (!to) return print("- Usage: request <handle> [note...]", "err");
    const note = args.slice(1).join(" ");

    if (!state.handle) return print("- Set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (!rec) return print("- No keys. Run genkeys", "err");

    const authenticated = await isAuthenticated();
    if (!authenticated) return;

    try {
      const rShow = await xfetch(`/v1/contacts/${encodeURIComponent(to)}`);
      if (!rShow.ok) throw new Error(`lookup ${rShow.status} (${(await rShow.json()).message})`);
      
      const { ps_b64, contact: is_contact } = await rShow.json();
      if (is_contact) throw new Error("duplication (Requestee is already a contact!)", "err");
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

      if (!r.ok) throw new Error(`HTTP ${r.status$} (${(await r.json()).message})`);
      
      const js = await r.json();
      print(`- Request sent to ${js.recipient_handle}!`, "ok");
    } 
    catch (e) { 
      print("- Request error: " + e.message, "err"); 
    }
  },

  async requests() {
    if (!state.handle) return print("- Set a handle first", "err");

    const authenticated = await isAuthenticated();
    if (!authenticated) return;

    try {
      const r = await xfetch("/v1/contacts/requests");
      if (!r.ok) throw new Error("HTTP " + r.status);
      const arr = await r.json();
      if (!arr.length) return print("- No pending requests", "muted");
      arr.forEach(it => print(`- id: ${it.id} from: ${it.from} ${it.note ? `note: "${it.note}" ` : ""}at=${it.at}`));
    } catch (e) { print("requests error: " + e.message, "err"); }
  },

  async accept(args) {
    const id = args[0];
    if (!id) return print("- Usage: accept <request_id>", "err");
    if (!state.handle) return print("- Set a handle first", "err");
    const rec = await loadKeys(state.handle);
    if (!rec) return print("No keys. Run genkeys","err");

    const authenticated = await isAuthenticated();
    if (!authenticated) return;

    try {
      const rs = await xfetch("/v1/contacts/requests");
      const list = await rs.json();
      const row = list.find(r => String(r.id) === String(id));
      if (!row) throw new Error("unknown request id", "err");


      const rShow = await xfetch(`/v1/contacts/${encodeURIComponent(row.from)}`)
      if (!rShow.ok) throw new Error("lookup " + rShow.status);
      const { ps_b64: from_ps_b64, contact: is_contact, handle: to } = await rShow.json();
      if (is_contact) return print("requestee is already a contact!", "err");

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
      print(`- @${to} added as a contact!`, "ok");

      // pull fresh contacts from server
      await syncContacts(state.handle);
    }
    catch (e) {
      print("- Accept error: " + e.message, "err");
    }
  },

  async decline(args) {
    const id = args[0];
    if (!id) return print("- Usage: decline <request_id>", "err");
    if (!state.handle) return print("- Set a handle first", "err");

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
      print(`- Contact request declined!`, "ok");
    }
    catch (e) {
      print("- Decline error: " + e.message, "err");
    }
  },

  async contacts() {
    if (!state.handle) return print("- Set a handle first", "err");

    const authenticated = await isAuthenticated();
    if (!authenticated) return; 

    try {
      await syncContacts(state.handle);
      const list = await listContactsLocal(state.handle);
      if (!list.length) return print("- No contacts", "muted");
      list.forEach(c => {
        print(`@${c.handle}`);
      });
    }
    catch (e) {
      print("- Contacts error: " + e.message, "err");
    }
  },

  async inbox() {
    if (!state.handle) return print("- Set a handle first", "err");
    const authenticated = await isAuthenticated();
    if (!authenticated) return;
    try {
      const arr = await inboxSummary();
      if (!arr.length) return print("- No chats yet", "muted");
      for (const it of arr) {
        const badge = it.unread > 0 ? ` [${it.unread} new]` : " [no new]";
        print(`@${it.handle}${badge}`);
      }
      print("Open a chat: chat <handle>")
    }
    catch (e) {
      print("inbox error: " + e.message, "err")
    }
  },

  async chat(args) {
    const peer = args[0];
    if (!peer) return print("- Usage: chat <handle>", "err");
    if (!state.handle) return print("- Set a handle first", "err");

    const authenticated = await isAuthenticated();
    if (!authenticated) return;

    try {
      let rec = await getContactFor(state.handle, peer);
      if (!rec) {
        const r = await xfetch(`/v1/contacts/${encodeURIComponent(peer)}`);
        if (!r.ok) throw new Error(`lookup ${r.status} (${(await r.json()).message})`);
        rec = await r.json();
      }

      const owner = state.handle;
      // ensure room exists and decrypt initial history only if needed
      const num_new = await ensureLocalHistory(owner, peer);
      const conv = await getConversation(owner, peer);
      if (!conv) throw new Error("no conversation");

      // Clear screen and enter chat mode
      term.innerHTML = "";
      print(`Chatting with @${peer}!`, "ok");
      print(`To quit type /q`, "muted");

      let added = await syncNewFromServer(owner, peer, conv.conversation_id);
      added ||= num_new;

      // subcribe to live chat
      if (!window.Cable) print("⚠️ ActionCable not loaded", "err");
      chatState?.sub?.unsubscribe?.();
      chatState = { peer, convoId: conv.conversation_id, sub: subscribeChat(conv.conversation_id, owner, peer) };
      
      await renderLocalChat(owner, peer, added);

      // Mark read
      markRead(conv.conversation_id, owner, peer);
    }
    catch (e) {
      print("chat error: " + e.message, "err");
    }
  }
}

// ---------- REPL ----------
input.addEventListener("keydown", async (e) => {
  if (e.key !== "Enter") return;
  const raw = input.value.trim();
  input.value = "";

  if (chatState) {
    if (raw === "/q") {
      // leave chat
      chatState.sub?.unsubscribe?.();
      chatState = null;
      term.innerHTML = "";
      banner();
      return;
    }
    // otherwise send messages to chatState.peer
    if (!raw) return;

    const to = chatState.peer;
    const text = raw;

    const sentId = await sendMessageAndGetId(to, text);
    const t = Date.now();
    const k = dayKey(t);
    if (chatState?.lastDayKey !== k) {
      print(`—— ${dayLabel(t)} ——`, "muted")
      ensureChatStateDay(k);
    }
    printChat(`${new Date(t).toLocaleTimeString()} me`, text);
    // persist plaintext with server id
    await upsertPlainMessage(state.handle, to, { id: sentId, t, from: state.handle, to, text });
    return;
  }

  // Normal REPL
  printHTML('<span class="prompt">$</span> ' + raw);
  if (!raw) return;

  const [cmd, ...args] = raw.split(/\s+/);
  const fn = commands[cmd];
  if (fn) await fn(args);
  else    print("unknown command: " + cmd, "err");
});

banner();
setTimeout(() => input.focus(), 50);

export { renderLocalChat, upsertPlainMessage, putConversation, listChatLocal, dayKey };
