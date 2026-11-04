import test from "node:test";
import assert from "node:assert/strict";
import { SLEEP_AFTER_MS, rng, toolState } from "../../src/cat/base.ts";
import { DISPLAY_MODES } from "../../src/cat/display.ts";
import { KITTEN_LEAVE_MS, KITTEN_MAX, KITTEN_PLACES, KITTEN_STATES, cleanKittens, kittenOrder, kittenPlaceOf, kittenSlots, kittenStep, kittenView } from "../../src/cat/kittens.ts";
import { finite, load, same } from "./util.mjs";

// Subagent kittens, replayed from tests/fixtures/cat/kitten-cases.json (B-0) one event at a time, and the events a JSON file cannot hold.
const fx = load("kitten-cases.json");
const step = kittenStep;
const run = (events, list = []) => events.reduce((l, e) => step(l, e), list);
const ids = (list) => list.map((k) => k.id);
const K = (id, state = "working", born = 0, last = born, extra = {}) => ({ id, type: "", session: null, state, born, last, until: null, ...extra });
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };

test("the limits, the states and the places are the fixture's", () => {
  same({ max: KITTEN_MAX, leaveMs: KITTEN_LEAVE_MS, sleepAfterMs: SLEEP_AFTER_MS }, fx.limits, "limits");
  assert.deepEqual([...KITTEN_STATES], fx.states);
  same(KITTEN_PLACES, fx.places, "places");
});

test("every script replays event by event, and every order, view, clean, slot and place case from its own input", () => {
  assert.ok(fx.scripts.length >= 21 && fx.slots.length >= 25 && fx.views.length === 4 && fx.placeOf.length === 8);
  for (const s of fx.scripts) {
    let list = s.from;
    s.steps.forEach((st, i) => { list = step(list, st.ev); same(list, st.list, `${s.name}, event ${i + 1}`); });
  }
  for (const c of fx.order) assert.deepEqual(kittenOrder(c.list).map((k) => k.id), c.out, c.name);
  for (const c of fx.views) assert.deepEqual(kittenView(c.list, c.now).map((k) => k.id), c.out, c.name);
  for (const c of fx.cleans) same(cleanKittens(c.raw), c.out, c.name);
  for (const c of fx.slots) same(kittenSlots(c.place, c.kittens), c.out, c.name);
  for (const c of fx.placeOf) assert.equal(kittenPlaceOf(c.mode, c.expanded), c.out, `${c.mode} ${c.expanded}`);
});

test("a time that is not a finite number changes nothing (a JSON fixture cannot hold one), and a view at such a time hides nothing", () => {
  const list = [K("a"), K("b", "leaving", 1, 2, { until: 5 })];
  for (const t of [NaN, Infinity, -Infinity, "1", null, undefined, {}]) {
    for (const type of ["start", "tool", "permission", "resolved", "stop", "end", "sweep", "tick"]) same(step(list, { type, id: "a", session: "s", tool: "Grep", t }), list, `${type} t ${String(t)}`);
  }
  assert.equal(kittenView(list, NaN).length, 2);
  assert.equal(kittenView(list, "x").length, 2);
  assert.equal(kittenView(list, 4).length, 2);
  assert.equal(kittenView(list, 5).length, 1);
});

test("an event that is not an event, or has a type that is not known, returns the list as it is", () => {
  const list = [K("a")];
  for (const ev of [null, undefined, 7, "start", [], {}, { t: 1 }, { type: "bogus", t: 1 }, { type: "start", t: 1 }, { type: "start", id: "", t: 1 }, { type: "start", id: 7, t: 1 }, { type: "start", id: "x".repeat(129), t: 1 }]) same(step(list, ev), list, JSON.stringify(ev));
  same(step(null, { type: "tick", t: 1 }), []);
  same(step("junk", { type: "tick", t: 1 }), []);
});

test("a late event brings nothing back: a tool or permission event for an id that never started, or has left, creates nothing", () => {
  assert.deepEqual(step([], { type: "tool", id: "ghost", tool: "Bash", t: 5 }), []);
  assert.deepEqual(step([], { type: "permission", id: "ghost", t: 5 }), []);
  const gone = run([{ type: "start", id: "a1", t: 0 }, { type: "stop", id: "a1", t: 10 }, { type: "tick", t: 700 }]);
  assert.deepEqual(step(gone, { type: "tool", id: "a1", tool: "Bash", t: 800 }), []);
  const leaving = run([{ type: "start", id: "a1", t: 0 }, { type: "stop", id: "a1", t: 10 }]);
  assert.equal(step(leaving, { type: "tool", id: "a1", tool: "Bash", t: 20 })[0].state, "leaving", "while it is leaving, a late event changes nothing");
  assert.deepEqual(step(leaving, { type: "permission", id: "a1", t: 20 }), leaving);
});

test("the farewell lasts 600 ms: leaving, then gone at the next event from `until` on, and hidden by kittenView from that moment", () => {
  const s = run([{ type: "start", id: "a1", t: 0 }, { type: "start", id: "a2", t: 5 }, { type: "stop", id: "a1", t: 1000 }]);
  assert.deepEqual(s[0], { id: "a1", type: "", session: null, state: "leaving", born: 0, last: 1000, until: 1600 });
  assert.deepEqual(ids(step(s, { type: "tick", t: 1599 })), ["a1", "a2"]);
  assert.deepEqual(ids(step(s, { type: "tick", t: 1600 })), ["a2"]);
  assert.deepEqual(ids(kittenView(s, 1599)), ["a2", "a1"], "newest first; the leaving one is still drawn");
  assert.deepEqual(ids(kittenView(s, 1600)), ["a2"], "hidden from `until` on, with no event and no timer");
  assert.deepEqual(step(s, { type: "stop", id: "a1", t: 1100 }), s, "a second stop changes nothing");
});

test("a lost stop: the parent's stop or the session's end removes them, the sleep sweep removes the stale, and two sessions of one agent do not take each other's", () => {
  const s = run([{ type: "start", id: "a1", session: "s1", t: 0 }, { type: "start", id: "a2", session: "s2", t: 1 }, { type: "start", id: "a3", t: 2 }]);
  assert.deepEqual(ids(step(s, { type: "end", session: "s1", t: 9 })), ["a2"], "only that session's go, and the ones with no session (a3)");
  assert.deepEqual(step(s, { type: "end", t: 9 }), [], "no session: every kitten");
  assert.deepEqual(step(s, { type: "sweep", t: SLEEP_AFTER_MS + 2 }), [], "all three have been quiet for ten minutes or more");
  const fresh = step(s, { type: "tool", id: "a2", tool: "Bash", t: SLEEP_AFTER_MS });
  assert.deepEqual(ids(step(fresh, { type: "sweep", t: SLEEP_AFTER_MS + 5 })), ["a2"], "one that had a recent event stays");
});

test("at most eight kittens: a ninth start drops the oldest, whatever its state; a repeated start only refreshes", () => {
  let list = [];
  for (let i = 1; i <= 9; i++) list = step(list, { type: "start", id: "k" + i, t: i });
  assert.equal(list.length, KITTEN_MAX);
  assert.deepEqual(ids(list), ["k2", "k3", "k4", "k5", "k6", "k7", "k8", "k9"]);
  const again = step(list, { type: "start", id: "k5", agentType: "Plan", t: 50 });
  assert.equal(again.length, KITTEN_MAX);
  assert.deepEqual(again.find((k) => k.id === "k5"), { id: "k5", type: "Plan", session: null, state: "working", born: 5, last: 50, until: null });
});

test("the order is a kitten waiting on an approval first, then the newest", () => {
  const list = run([{ type: "start", id: "a", t: 1 }, { type: "start", id: "b", t: 2 }, { type: "start", id: "c", t: 3 }, { type: "permission", id: "a", t: 4 }]);
  assert.deepEqual(ids(kittenView(list, 10)), ["a", "c", "b"]);
  assert.equal(toolState("Grep"), "searching");
  assert.equal(step(list, { type: "tool", id: "b", tool: "WebSearch", t: 5 })[1].state, "searching");
});

test("the slots: nothing for an unknown place, and every place holds its numbers for 0 to 7 kittens, with no NaN", () => {
  for (const place of [...Object.keys(KITTEN_PLACES), "bogus", "", null, undefined, 7, "__proto__", "constructor"]) for (let n = 0; n <= 7; n++) {
    const out = kittenSlots(place, Array.from({ length: n }, (_, i) => K("k" + i)));
    finite(out);
    assert.ok(out.shown.length <= (KITTEN_PLACES[place]?.max ?? 0) && out.count === n);
    if (!(typeof place === "string" && Object.hasOwn(KITTEN_PLACES, place))) assert.deepEqual([out.unit, out.shown.length, out.more, out.moreAt, out.label], [null, 0, 0, null, null], String(place));
  }
  assert.equal(kittenSlots("pairCompact", [K("a"), K("b")]).label.text, "×2");
  assert.equal(kittenSlots("bigExpanded", Array.from({ length: 7 }, (_, i) => K("k" + i))).more, 4);
  for (const mode of DISPLAY_MODES) for (const expanded of [true, false]) assert.ok(Object.hasOwn(KITTEN_PLACES, kittenPlaceOf(mode, expanded)));
});

test("a frozen list is fine, and nothing is changed in place; 4000 random events keep every list valid", () => {
  const frozen = deepFreeze([K("a"), K("b", "approval", 2)]);
  assert.doesNotThrow(() => step(frozen, { type: "stop", id: "a", t: 9 }));
  assert.deepEqual(frozen, [K("a"), K("b", "approval", 2)]);
  const r = rng(77), types = ["start", "tool", "permission", "resolved", "stop", "end", "sweep", "tick", "bogus"], names = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "", 7, null];
  let list = [], t = 0;
  for (let i = 0; i < 4000; i++) {
    t += Math.floor(r() * 400_000);
    list = step(list, { type: types[Math.floor(r() * types.length)], id: names[Math.floor(r() * names.length)], session: r() < 0.3 ? "s" + Math.floor(r() * 3) : undefined, tool: r() < 0.5 ? "Grep" : "Bash", t: r() < 0.03 ? NaN : t });
    assert.ok(list.length <= KITTEN_MAX && new Set(ids(list)).size === list.length, `event ${i}`);
    assert.ok(list.every((k) => KITTEN_STATES.includes(k.state) && Number.isFinite(k.born) && Number.isFinite(k.last) && (k.state === "leaving") === (k.until !== null)), `event ${i}`);
  }
});
