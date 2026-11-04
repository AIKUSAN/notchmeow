import test from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_DESKTOP_SIZE, DESKTOP_ACTS, DESKTOP_ARC, DESKTOP_DEFAULT, DESKTOP_EVENTS, DESKTOP_FLIGHT_MS, DESKTOP_FPS, DESKTOP_KITTEN_PLACE, DESKTOP_MARGIN, DESKTOP_NEAR, DESKTOP_PHASES,
  DESKTOP_PHASE_INFO, DESKTOP_SIZES, DESKTOP_SIZE_IDS, MAX_DESKTOP_SPOTS, clampSpot, cleanDesktopSettings, cleanDesktopSpots, defaultDesktopSettings, defaultDesktopSpot, desktopFlightAt,
  desktopFps, desktopKittenSlots, desktopSizeOf, desktopStep, isScreenKey, rememberSpot, screenKey, spotFor,
} from "../../src/cat/desktop.ts";
import { finite, load, near, same } from "./util.mjs";

// The desktop cat's rules, replayed from tests/fixtures/cat/desktop-cases.json (H-0), and the inputs a JSON file cannot hold: NaN, infinities, text for a number.
const fx = load("desktop-cases.json");
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
const LAPTOP = [{ frame: { x: 0, y: 0, w: 1512, h: 982 }, visible: { x: 0, y: 37, w: 1512, h: 875 }, main: true }];

test("the constants, the phases, the events and the acts are the fixture's", () => {
  assert.deepEqual([...DESKTOP_PHASES], fx.phaseIds);
  assert.deepEqual([...DESKTOP_EVENTS], fx.events);
  assert.deepEqual([...DESKTOP_ACTS], fx.acts);
  same(DESKTOP_PHASE_INFO, fx.phases, "phases");
  same({ flightMs: DESKTOP_FLIGHT_MS, arc: DESKTOP_ARC, sizes: DESKTOP_SIZES, fps: DESKTOP_FPS, near: DESKTOP_NEAR, kittenPlace: DESKTOP_KITTEN_PLACE, margin: DESKTOP_MARGIN, maxSpots: MAX_DESKTOP_SPOTS },
    { flightMs: fx.flightMs, arc: fx.arc, sizes: fx.sizes, fps: fx.fps, near: fx.near, kittenPlace: fx.kittenPlace, margin: fx.margin, maxSpots: fx.maxSpots }, "numbers");
  same(DESKTOP_DEFAULT, fx.defaultSpot, "default spot");
  assert.deepEqual([...DESKTOP_SIZE_IDS], fx.sizeIds);
  assert.equal(DEFAULT_DESKTOP_SIZE, fx.defaultSize);
});

test("desktopStep replays all steps (every phase and event, and input that is neither) and every trip, event by event", () => {
  assert.ok(fx.steps.length >= 89 && fx.trips.length >= 11);
  for (const c of fx.steps) same(desktopStep(c.state, c.event), c.out, `${JSON.stringify(c.state)} ${JSON.stringify(c.event)}`);
  for (const t of fx.trips) {
    let state = t.from;
    t.events.forEach((ev, i) => { const r = desktopStep(state, ev); same(r, t.out[i], `${t.name}, event ${i + 1}`); state = r.state; });
  }
});

test("a phase that is drawn has an empty notch spot, 'on' is stored for every phase but the two homes, and a flight is exactly a change between flights", () => {
  for (const p of DESKTOP_PHASES) {
    const i = DESKTOP_PHASE_INFO[p];
    if (i.drawn) assert.equal(i.notchEmpty, true, `${p}: never two copies of one cat`);
    assert.equal(i.flight, i.dir !== null, p);
  }
  assert.deepEqual(DESKTOP_PHASES.filter((p) => !DESKTOP_PHASE_INFO[p].on), ["home", "flyingHome"]);
  // 'turn' is a change between two flights whose direction differs, 'keep' between two with the same direction.
  for (const s of fx.steps) {
    if (s.out.act !== "turn" && s.out.act !== "keep") continue;
    const a = DESKTOP_PHASE_INFO[s.state], b = DESKTOP_PHASE_INFO[s.out.state];
    assert.ok(a.flight && b.flight, `${s.state} ${s.event.type}`);
    assert.equal(s.out.act === "turn", a.dir !== b.dir, `${s.state} ${s.event.type}`);
  }
});

test("a drop or a move without a valid spot changes nothing, and the machine never throws on anything", () => {
  for (const spot of [undefined, null, 5, "x", {}, { x: 1 }, { x: NaN, y: 1 }, { x: 1, y: Infinity }, { x: "1", y: 2 }, { x: 1e5 + 1, y: 0 }, [1, 2]]) {
    same(desktopStep("home", { type: "dragOut", spot }), { state: "home", act: null }, `dragOut ${JSON.stringify(spot)}`);
    same(desktopStep("onDesktop", { type: "move", spot }), { state: "onDesktop", act: null }, `move ${JSON.stringify(spot)}`);
  }
  same(desktopStep("home", { type: "dragOut", spot: { x: 1e5, y: -1e5 } }), { state: "onDesktop", act: "place" }, "the limit itself is a spot");
  for (const state of [undefined, null, 7, {}, [], "constructor", "__proto__", "HOME"]) for (const ev of [undefined, null, 3, "toggle", [], {}, { type: 7 }, { type: "constructor" }, { type: "__proto__" }, { type: "toggle" }]) {
    const r = desktopStep(state, ev);
    assert.ok(DESKTOP_PHASES.includes(r.state), `${String(state)} ${JSON.stringify(ev)}`);
  }
  same(desktopStep("constructor", { type: "toggle" }), { state: "flyingOut", act: "flyOut" }, "a state that is not a phase counts as home");
});

test("desktopFlightAt replays the fixture, holds t to 0..1, and a flight retraces itself when its ends are swapped", () => {
  assert.ok(fx.flights.length >= 80);
  for (const c of fx.flights) same(desktopFlightAt(c.from, c.to, c.t), c.out, `${c.name} t ${c.t}`);
  const a = { x: 480, y: 16 }, b = { x: 576, y: 180 };
  for (let i = 0; i <= 20; i++) {
    const t = i / 20, p = desktopFlightAt(a, b, t), q = desktopFlightAt(b, a, 1 - t);
    near(p.x, q.x); near(p.y, q.y); assert.equal(p.scale, 1);
  }
});

test("a flight with a t, a from or a to that is not a number is the default, and nothing is ever NaN: what a JSON fixture cannot hold", () => {
  const a = { x: 10, y: 20 }, b = { x: 300, y: 400 };
  for (const t of [NaN, "0.5", null, undefined, {}, [], true]) same(desktopFlightAt(a, b, t), desktopFlightAt(a, b, 0), `t ${String(t)}`);
  same(desktopFlightAt(a, b, Infinity), desktopFlightAt(a, b, 1), "+Infinity is held to 1");
  same(desktopFlightAt(a, b, -Infinity), desktopFlightAt(a, b, 0), "-Infinity is held to 0");
  for (const bad of [null, undefined, 5, "x", {}, { x: NaN, y: 0 }, { x: 0, y: Infinity }, { x: "1", y: 1 }]) {
    same(desktopFlightAt(bad, b, 0.4), desktopFlightAt({ x: 0, y: 0 }, b, 0.4), `from ${JSON.stringify(bad)}`);
    same(desktopFlightAt(a, bad, 0.4), desktopFlightAt(a, { x: 0, y: 0 }, 0.4), `to ${JSON.stringify(bad)}`);
  }
  finite(desktopFlightAt(a, a, 0.5));
  finite(desktopFlightAt({ x: 1e5, y: 1e5 }, { x: -1e5, y: -1e5 }, 0.5));
});

test("sizes: the three IDs, and anything else (a number, text in another case, a list, __proto__) is medium", () => {
  for (const c of fx.sizeCases) assert.equal(desktopSizeOf(c.raw), c.out, JSON.stringify(c.raw));
  for (const raw of [undefined, null, NaN, 48, "Small", "SMALL", " small", "small ", ["small"], { 0: "small" }, "toString"]) assert.equal(desktopSizeOf(raw), "medium", String(raw));
});

test("desktopFps replays the fixture and treats only true as a flag and only a finite number as a distance", () => {
  assert.ok(fx.fpsCases.length >= 39);
  for (const c of fx.fpsCases) assert.equal(desktopFps(c.input), c.out, c.name);
  const base = { phase: "onDesktop" };
  for (const flag of ["hidden", "dragging", "emote", "kittenMotion", "dance", "asleep", "working"]) {
    for (const v of [1, "true", {}, [], null, undefined, "yes"]) assert.equal(desktopFps({ ...base, [flag]: v }), DESKTOP_FPS.idle, `${flag} ${JSON.stringify(v)}`);
    assert.notEqual(desktopFps({ ...base, [flag]: true }), DESKTOP_FPS.idle, `${flag} true`);
  }
  for (const d of [NaN, Infinity, -Infinity, "10", null, undefined, {}, DESKTOP_NEAR + 0.001]) assert.equal(desktopFps({ ...base, cursorDist: d }), DESKTOP_FPS.idle, `cursorDist ${String(d)}`);
  assert.equal(desktopFps({ ...base, cursorDist: DESKTOP_NEAR }), DESKTOP_FPS.active, "within 150 is inclusive");
  assert.equal(desktopFps({ ...base, asleep: true, cursorDist: 5, working: true }), DESKTOP_FPS.asleep, "sleep beats the cursor and work");
  assert.equal(desktopFps({ ...base, asleep: true, hidden: true }), 0, "hidden beats everything");
  for (const i of [undefined, null, 5, "onDesktop", [], {}, { phase: "nope" }, { phase: "constructor" }, { phase: undefined }]) assert.equal(desktopFps(i), 0, JSON.stringify(i));
});

test("desktopKittenSlots replays the fixture, scales with the size, and mirrors for a cat in the right half of its screen", () => {
  assert.ok(fx.kittenSlots.length >= 21);
  for (const c of fx.kittenSlots) same(desktopKittenSlots(c.kittens, c.side), c.out, c.name);
  assert.equal(fx.kittenSizes.length, 12);
  for (const c of fx.kittenSizes) {
    const ks = Array.from({ length: c.count }, (_, i) => ({ id: `k${i}`, state: ["approval", "searching", "working"][i % 3] })), s = desktopKittenSlots(ks, 1);
    same({ count: s.count, more: s.more, shown: s.shown.map((q) => ({ id: q.id, state: q.state, x: q.x * c.d, y: q.y * c.d, d: q.d * c.d })), moreAt: s.moreAt && { x: s.moreAt.x * c.d, y: s.moreAt.y * c.d, size: s.moreAt.size * c.d } },
      { count: c.count, more: c.more, shown: c.shown, moreAt: c.moreAt }, `${c.size} ${c.count}`);
  }
  for (const side of [undefined, 0, 2, "-1", null, NaN]) same(desktopKittenSlots([{ id: "a" }], side), desktopKittenSlots([{ id: "a" }], 1), `side ${String(side)} is 1`);
  assert.deepEqual(desktopKittenSlots("nope", 1).shown, [], "a list that is not a list shows nothing");
  assert.equal(desktopKittenSlots([{ id: "" }, { id: 5 }, null, { id: "ok" }], 1).count, 1, "only real kitten IDs count");
});

test("screenKey, isScreenKey, clampSpot, defaultDesktopSpot, spotFor and rememberSpot replay the fixture", () => {
  assert.equal(fx.screenKeys.length >= 19 && fx.isScreenKey.length >= 30 && fx.clamps.length >= 54 && fx.defaultSpots.length >= 8 && fx.spotFor.length >= 13 && fx.remembers.length >= 8, true);
  for (const c of fx.screenKeys) assert.equal(screenKey(c.screens), c.out, c.name);
  for (const c of fx.isScreenKey) assert.equal(isScreenKey(c.key), c.out, JSON.stringify(c.key));
  for (const c of fx.clamps) same(clampSpot(c.spot, c.screens, c.size), c.out, c.name);
  for (const c of fx.defaultSpots) same(defaultDesktopSpot(c.screens, c.size), c.out, c.name);
  for (const c of fx.spotFor) same(spotFor(c.spots, c.screens, c.size), c.out, c.name);
  for (const c of fx.remembers) same(rememberSpot(c.spots, c.screens, c.spot, c.size), c.out, c.name);
});

test("spots with numbers a JSON file cannot hold: a spot that is NaN or infinite is on no screen, and a screen that is NaN is no screen", () => {
  const d = defaultDesktopSpot(LAPTOP, "medium");
  for (const spot of [{ x: NaN, y: 100 }, { x: 100, y: Infinity }, { x: "100", y: 100 }, null, undefined]) same(clampSpot(spot, LAPTOP, "medium"), d, JSON.stringify(spot));
  const bad = [{ frame: { x: NaN, y: 0, w: 100, h: 100 } }, { frame: { x: 0, y: 0, w: Infinity, h: 100 } }, { frame: { x: 0, y: 0, w: 0, h: 100 } }, { frame: { x: 0, y: 0, w: 1e6 + 1, h: 100 } }, null, 7];
  assert.equal(screenKey(bad), "");
  assert.equal(clampSpot({ x: 5, y: 5 }, bad, "medium"), null);
  assert.equal(spotFor({}, bad, "medium"), null);
  assert.equal(defaultDesktopSpot(bad), null);
  assert.deepEqual(rememberSpot({ "0,0,1,1": { x: 1, y: 1 } }, bad, { x: 5, y: 5 }), { "0,0,1,1": { x: 1, y: 1 } });
  // Half up, not half away from zero: -0.5 rounds to 0 and -1.5 to -1.
  assert.equal(screenKey([{ frame: { x: -0.5, y: -1.5, w: 10.5, h: 10.4 } }]), "0,-1,11,10");
  // The cat's centre is margin + D/2 from every edge of the visible frame, for each size.
  for (const [id, D] of Object.entries(DESKTOP_SIZES)) {
    const c = clampSpot({ x: 0, y: 0 }, LAPTOP, id), m = DESKTOP_MARGIN + D / 2;
    near(c.x, m); near(c.y, 37 + m);
    const r = clampSpot({ x: 1511, y: 981 }, LAPTOP, id);
    near(r.x, 1512 - m); near(r.y, 912 - m);
  }
});

test("nothing is changed in place, and a stored map is cleaned the same however it is written", () => {
  const spots = deepFreeze(JSON.parse('{"0,0,1512,982":{"x":300,"y":400,"extra":1},"__proto__":{"x":1,"y":1}}'));
  const before = JSON.stringify(spots);
  rememberSpot(spots, LAPTOP, { x: 10, y: 10 }, "large"); spotFor(spots, LAPTOP, "small"); cleanDesktopSpots(spots); deepFreeze(LAPTOP); clampSpot({ x: 1, y: 1 }, LAPTOP, "large"); screenKey(LAPTOP);
  assert.equal(JSON.stringify(spots), before);
  for (const c of fx.spotMaps) { same(cleanDesktopSpots(c.raw), c.out, c.name); if (c.raw !== null && typeof c.raw === "object" && !Array.isArray(c.raw)) same(cleanDesktopSpots(JSON.stringify(c.raw)), c.out, `${c.name} as JSON text`); }
  for (const text of ["{not json", "", "null", "[1]", "7", "\"x\""]) assert.deepEqual(cleanDesktopSpots(text), {}, JSON.stringify(text));
  const many = {};
  for (let i = 0; i < 300; i++) many[`${i},0,100,100`] = { x: i, y: i };
  const keys = Object.keys(cleanDesktopSpots(many));
  assert.equal(keys.length, MAX_DESKTOP_SPOTS);
  assert.deepEqual(keys, [...keys].sort(), "code-point order");
  const full = rememberSpot(many, LAPTOP, { x: 100, y: 100 }, "medium");
  assert.equal(Object.keys(full).length, MAX_DESKTOP_SPOTS);
  assert.ok("0,0,1512,982" in full, "the arrangement just written is always kept");
});

test("cleanDesktopSettings replays the fixture; 'on' is only the boolean true; the defaults are medium, off, no spots", () => {
  same(defaultDesktopSettings(), fx.settingsDefaults, "defaults");
  assert.ok(fx.settingsCases.length >= 41);
  for (const c of fx.settingsCases) { same(cleanDesktopSettings(c.raw), c.out, c.name); same(cleanDesktopSettings(cleanDesktopSettings(c.raw)), c.out, `${c.name} twice`); }
  for (const on of [1, "true", "1", [], {}, null, undefined, 0.5]) assert.equal(cleanDesktopSettings({ on }).on, false, JSON.stringify(on));
  for (const raw of [undefined, null, 5, "x", [], [{ on: true }], true]) same(cleanDesktopSettings(raw), fx.settingsDefaults, JSON.stringify(raw));
});
