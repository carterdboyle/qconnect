import { jest, expect, test, beforeEach } from "@jest/globals";

document.body.innerHTML = `<div id="terminal"></div><input id="input" />`;
global.term = document.getElementById("terminal");

global.print = (t, c = "") => {
  const d = document.createElement("div");
  d.className = `line ${c}`;
  d.textContent = t;
  term.appendChild(d);
}

global.printChat = (preface, text) => {
  const d = document.createElement("div");
  d.className = "line chat";
  d.textContent = `${preface}: ${text}`;
  term.appendChild(d);
}

global.printDayDivider = (t) => {
  const d = document.createElement("div");
  d.className = "line divider";
  d.textContent = `—— ${new Date(t).toDateString()} ——`;
  term.appendChild(d);
}
global.ensureChatStateDay = () => {};

// Mock actioncable that file imports
jest.unstable_mockModule("@rails/actioncable", () => ({
  createConsumer: () => ({ subscriptions: { create: () => ({ unsubscribe: () => {} }) } })
}));

const mod = await import("../../app/javascript/terminal.js")
const {
  renderLocalChat,
  upsertPlainMessage,
  putConversation,
  dayKey
} = mod;

// Utility to reset the terminal between tests
beforeEach(() => {
  term.innerHTML = "";
})

test("prints 'X new messages!' right before the first newly-synced message; header appears before day divider if new messages start a new day", async () => {
  const owner = "alice";
  const peer = "bob";

  // Build a deterministic timeline:
  // [yesterday: read], then [today: two new messages]
  const tYesterday = Date.UTC(2025, 10, 1, 10, 0, 0, 0);
  const tToday1 = Date.UTC(2025, 10, 2, 9, 5, 0, 0);
  const tToday2 = Date.UTC(2025, 10, 2, 10, 5, 0, 0);

  await upsertPlainMessage(owner, peer, { id: 1, t: tYesterday, from: peer, to: owner, text: "y1"});
  await upsertPlainMessage(owner, peer, { id: 2, t: tToday1, from: peer, to: owner, text: "t1"});
  await upsertPlainMessage(owner, peer, { id: 3, t: tToday2, from: peer, to: owner, text: "t2"});

  await putConversation(owner, peer, {
    conversation_id: 1,
    last_read_id: 1,
    last_read_t: tYesterday
  });

  const added = 2;
  await renderLocalChat(owner, peer, added);

  const lines = [...term.querySelectorAll(".line")].map(el => el.textContent);
  
  // Expect: order is
  // divider(yesterday)
  // chat(y1)
  // "2 new messages!"
  // divider(today)
  // chat(t1)
  // chat(t2)

  // helpers to find thigns
  const bannerIdx = lines.findIndex(t => /2 new messages!/.test(t));
  const yDivIdx = lines.findIndex(t => /—— .* ——/.test(t) && dayKey(new Date(t.replace(/^—— | ——$/g,"")).getTime()) === dayKey(tYesterday));
  const tDivIdx = lines.findIndex(t => /—— .* ——/.test(t) && dayKey(new Date(t.replace(/^—— | ——$/g,"")).getTime()) === dayKey(tToday1));
  const yMsgIdx = lines.findIndex(t => /@bob: y1$/.test(t) || /me: t1$/.test(t));
  const t1MsgIdx = lines.findIndex(t => /@bob: t1$/.test(t) || /me: t2$/.test(t));
  const t2MsgIdx = lines.findIndex(t => /@bob: t2$/.test(t) || /me: t2$/.test(t));

  // Sanity checks
  expect(yDivIdx).toBeGreaterThan(-1);
  expect(tDivIdx).toBeGreaterThan(-1);
  expect(yMsgIdx).toBeGreaterThan(-1);
  expect(t1MsgIdx).toBeGreaterThan(-1);
  expect(t2MsgIdx).toBeGreaterThan(-1);

  // positions
  expect(yDivIdx).toBeLessThan(yMsgIdx);
  expect(yMsgIdx).toBeLessThan(bannerIdx);
  expect(bannerIdx).toBeLessThan(tDivIdx);
  expect(tDivIdx).toBeLessThan(t1MsgIdx);
  expect(t1MsgIdx).toBeLessThan(t2MsgIdx);
})