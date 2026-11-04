import test from "node:test";
import assert from "node:assert/strict";
import { LINK_EMPTY, LinkStore, cardTransition, cleanSnapshot, holdsIsland, offerPending, sendTargets, shownOf, showDeviceButton } from "../../src/link/model.ts";
import { mockLinkBackend } from "../../src/link/mock.ts";
import { percent, permissionHelp, readCode, spaced, stateWords } from "../../src/link/text.ts";
import { CARDS, ROWS } from "../../src/link/devseed.ts";

// The link as the page holds it (G2): the snapshot Rust sends is cleaned, never thrown at; the island's rule for a card; the words of the cards.

test("a snapshot is whatever Rust said, cleaned: unknown shapes are dropped and nothing throws", () => {
  for (const bad of [null, undefined, 5, "x", [], true]) assert.deepEqual(cleanSnapshot(bad), LINK_EMPTY);
  const s = cleanSnapshot({
    visible: true, name: "Desk PC", listening: 1, problem: 7, note: "n", sendStatus: ["x"], sending: "yes", folder: "C:\\Downloads\\NotchMeow",
    rows: [{ id: "a", name: "A", state: "pairedOnline" }, { id: "b", name: "B", state: "ghost" }, null, { id: 3, name: "C", state: "available" }, "x"],
    card: { kind: "offer", key: "k", name: "a.txt", size: 12, received: -4, answered: "yes", extra: "dropped" },
  });
  assert.equal(s.visible, true);
  assert.equal(s.listening, false, "only the boolean true counts");
  assert.equal(s.problem, null);
  assert.equal(s.sendStatus, null);
  assert.equal(s.sending, false);
  assert.deepEqual(s.rows, [{ id: "a", name: "A", state: "pairedOnline" }]);
  assert.deepEqual(s.card, { kind: "offer", key: "k", name: "a.txt", size: 12 }, "a negative count and a non-boolean flag are left out, an unknown field is dropped");
  assert.equal(cleanSnapshot({ card: { kind: "weird", key: "k" } }).card, null);
  assert.equal(cleanSnapshot({ card: { kind: "pair" } }).card, null, "a card with no key is no card");
});

test("a long text is cut, so a hostile peer's name cannot fill the page", () => {
  const s = cleanSnapshot({ card: { kind: "pair", key: "k", peer: "x".repeat(5000), code: "1".repeat(50) }, rows: [{ id: "a", name: "y".repeat(5000), state: "available" }] });
  assert.equal(s.card.peer.length, 200);
  assert.equal(s.card.code.length, 12);
  assert.equal(s.rows[0].name.length, 200);
});

test("which cards hold the island, and which is an alert", () => {
  for (const [name, c] of Object.entries(CARDS)) {
    assert.equal(holdsIsland(c), !["received", "paired", "notPaired", "expired", "cancelled", "stopped"].includes(name), name);
    assert.equal(offerPending(c), name === "offer" || name === "offerLong", name);
  }
  assert.equal(holdsIsland(null), false);
  assert.equal(offerPending(null), false);
});

test("the island's rule for a card: a new card or a new kind opens it, the same kind again does not, a card with buttons holds it, the end lets it go", () => {
  const T = (prev, next, link = false) => cardTransition(prev ? CARDS[prev] : null, next ? CARDS[next] : null, link);
  assert.deepEqual(T(null, "offer"), { alert: true, hold: true, release: false, collapse: false }, "an offer arrives");
  assert.deepEqual(T("offer", "receiving45"), { alert: true, hold: true, release: false, collapse: false }, "a change of kind (offer to receiving) opens it again");
  assert.deepEqual(T("receiving0", "receiving45"), { alert: false, hold: true, release: false, collapse: false }, "progress is the same kind: nothing opens");
  assert.deepEqual(T("pair", "pairAnswered"), { alert: false, hold: true, release: false, collapse: false }, "the user's own answer is the same kind");
  assert.deepEqual(T("receiving100", "received"), { alert: true, hold: false, release: true, collapse: false }, "the end: a result, no hold");
  assert.deepEqual(T("received", null, true), { alert: false, hold: false, release: false, collapse: true }, "a card that goes while the link view shows closes the island");
  assert.deepEqual(T("received", null, false), { alert: false, hold: false, release: false, collapse: false }, "and not when the island shows something else");
  assert.deepEqual(T("offer", null, true), { alert: false, hold: false, release: true, collapse: true }, "an offer withdrawn");
});

test("the shelf offers the machines that are paired and online, and the device button shows when the link is on or a machine is paired", () => {
  assert.deepEqual(sendTargets(ROWS.two).map((r) => r.name), ["Sam's MacBook Pro", "Studio laptop"]);
  assert.deepEqual(sendTargets(ROWS.offline), []);
  assert.equal(showDeviceButton({ ...LINK_EMPTY }), false, "nothing on, nobody paired");
  assert.equal(showDeviceButton({ ...LINK_EMPTY, visible: true }), true);
  assert.equal(showDeviceButton({ ...LINK_EMPTY, rows: ROWS.offline }), true);
  assert.equal(showDeviceButton({ ...LINK_EMPTY, rows: [{ id: "x", name: "X", state: "available" }] }), false, "a machine only seen is not a destination");
});

test("a click carries the card it was meant for: its kind and what it is about", () => {
  assert.deepEqual(shownOf(CARDS.offer), { kind: "offer", key: CARDS.offer.key });
});

test("the store keeps the last snapshot, tells the island only about a real change, and reads the first state at once", async () => {
  let notified = 0;
  const seen = [];
  const store = new LinkStore(() => notified++);
  const mock = mockLinkBackend({ visible: true });
  store.attach(mock, (prev, next) => seen.push([prev.card?.kind ?? null, next.card?.kind ?? null]));
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(store.snapshot.visible, true);
  const base = notified;
  mock.set({ card: CARDS.offer });
  mock.set({ card: CARDS.offer }); // the same again
  assert.equal(notified, base + 1, "an identical snapshot changes nothing");
  assert.deepEqual(seen.at(-1), [null, "offer"]);
  assert.equal(store.offerPending, true);
  mock.set({ card: null });
  assert.equal(store.offerPending, false);
});

test("a state() reply that comes after a pushed snapshot does not overwrite it; with no push the reply applies", async () => {
  const older = { ...LINK_EMPTY, name: "Desk PC", visible: false };
  const newer = { ...older, visible: true, listening: true };
  // The reply is computed first and delivered last: the push (newer) overtakes it.
  let reply;
  let push;
  const late = {
    ...mockLinkBackend(),
    state: () => new Promise((r) => { reply = r; }),
    onSnapshot: (cb) => { push = cb; return () => {}; },
  };
  const store = new LinkStore();
  store.attach(late);
  push(newer);
  reply(older);
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(store.snapshot.visible, true, "the older reply did not replace the pushed snapshot");
  // Nothing pushed: the reply is the first state and applies.
  const quiet = { ...mockLinkBackend(), state: async () => older, onSnapshot: () => () => {} };
  const second = new LinkStore();
  second.attach(quiet);
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(second.snapshot.name, "Desk PC");
});

test("the stand-in link refuses a name a card would refuse, records the calls, and forgets a machine", async () => {
  const mock = mockLinkBackend({ rows: ROWS.two });
  assert.equal(await mock.setName(" padded"), false);
  assert.equal(await mock.setName("a\u202eb"), false);
  assert.equal(await mock.setName("x".repeat(64)), false);
  assert.equal(await mock.setName("Studio PC"), true);
  assert.equal(mock.snapshot.name, "Studio PC");
  mock.forget(ROWS.two[0].id);
  assert.equal(mock.snapshot.rows.length, 3);
  mock.respondOffer(true, shownOf(CARDS.offer));
  assert.match(mock.calls.at(-1), /^respondOffer true /);
});

test("the words of the cards", () => {
  assert.equal(spaced("483291"), "483 291");
  assert.equal(spaced("12"), "12", "not six digits: as it is");
  assert.equal(readCode("483291"), "4 8 3 2 9 1");
  assert.equal(percent(0, 100), 0);
  assert.equal(percent(1080000, 2400000), 45);
  assert.equal(percent(5, 0), 100, "an empty file is done");
  assert.equal(percent(200, 100), 100);
  assert.equal(percent(-5, 100), 0);
  assert.equal(stateWords("pairedOnline"), "Paired");
  assert.equal(stateWords("pairedOffline"), "Paired, not seen");
  assert.equal(stateWords("available"), "Available");
  assert.match(permissionHelp("windows"), /Windows Defender Firewall/);
  assert.match(permissionHelp("linux"), /5353/);
});

import fs from "node:fs";

// The one sample file that Rust and the page both read (Rust: src-tauri/src/link/service.rs, `the_snapshot_the_page_gets_is_the_sample_file`): what Rust serializes is what the page keeps whole.
test("every sample snapshot of the shared file is kept whole by the page's clean-up", () => {
  const samples = JSON.parse(fs.readFileSync(new URL("./snapshot-samples.json", import.meta.url), "utf8"));
  assert.ok(samples.length >= 6);
  for (const s of samples) assert.deepEqual(cleanSnapshot(s.snapshot), s.snapshot, s.name);
});
