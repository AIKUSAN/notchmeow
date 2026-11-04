import test from "node:test";
import assert from "node:assert/strict";
import { DESKTOP_PHASE_INFO, DESKTOP_PHASES, defaultDesktopSettings, desktopStep, spotFor } from "../../src/cat/desktop.ts";
import { DOUBLE_MS, DRAG_PX, Gestures } from "../../src/cat/gestures.ts";
import { SURPRISE_MS, DesktopTrip } from "../../src/cat/desktoptrip.ts";

// The trip as the island runs it: a fake environment records every message to the desktop window, every save and every change of the notch's big-cat spot.
const LAPTOP = [{ frame: { x: 0, y: 0, w: 1512, h: 982 }, visible: { x: 0, y: 37, w: 1512, h: 875 }, main: true }];
const NOTCH = { x: 756, y: 16 };
function world(over = {}) {
  const w = { settings: defaultDesktopSettings(), sent: [], saves: 0, empty: [], notch: NOTCH, screens: LAPTOP, ...over };
  w.env = {
    body: (m) => w.sent.push(m), notchSpot: () => w.notch, screens: () => w.screens, settings: () => w.settings,
    save: (s) => { w.settings = s; w.saves++; }, notchEmpty: (e) => w.empty.push(e),
  };
  w.trip = new DesktopTrip(w.env);
  return w;
}
const kinds = (w) => w.sent.map((m) => m.k);

// The island's own saves come back: Rust emits `settings-changed` for every save to every window, the island's included, and its handler overwrites the local settings with the echoed
// block and then calls `sync()`. `echoWorld` is `world` with that wire: every save is queued, and `flush()` plays the echoes in order, each as the handler does (settings first, then sync).
function echoWorld(over = {}) {
  const w = world(over), queued = [];
  const save = w.env.save;
  w.env.save = (s) => { save(s); queued.push(s); };
  w.flush = () => {
    for (let guard = 0; queued.length && guard < 50; guard++) { w.settings = queued.shift(); w.trip.sync(); }
    assert.equal(queued.length, 0, "the echoes settle");
  };
  return w;
}

test("taking the cat out from the menu: it flies from the notch to its default spot, the notch spot empties, 'out' is stored, and the landing changes nothing on screen", () => {
  const w = world();
  w.trip.toggle();
  assert.equal(w.trip.phase, "flyingOut");
  const want = spotFor({}, LAPTOP, "medium");
  assert.deepEqual(w.sent, [{ k: "fly", from: NOTCH, to: want, dir: "out" }]);
  assert.equal(w.settings.on, true);
  assert.equal(w.empty.at(-1), true);
  w.trip.flightDone();
  assert.equal(w.trip.phase, "onDesktop");
  assert.equal(w.sent.length, 1, "land sends nothing: the window is already there");
});

test("a drop on the desktop places the cat, held on the screen, and remembers the spot for these screens without a flight", () => {
  const w = world();
  w.trip.dragOut({ x: 5, y: 5 });
  assert.equal(w.trip.phase, "onDesktop");
  assert.deepEqual(w.sent, [{ k: "show", spot: { x: 56, y: 93 } }], "held 24 points from the head's edge, below the menu bar");
  assert.deepEqual(w.settings.spots, { "0,0,1512,982": { x: 56, y: 93 } });
  assert.equal(w.settings.on, true);
  // A move saves the new spot; a drop that is not a spot changes nothing.
  w.trip.move({ x: 700, y: 400 });
  assert.deepEqual(w.settings.spots["0,0,1512,982"], { x: 700, y: 400 });
  assert.deepEqual(w.sent.at(-1), { k: "show", spot: { x: 700, y: 400 } });
  const n = w.sent.length;
  w.trip.move({ x: NaN, y: 400 });
  w.trip.dragOut({ x: 1, y: 1 });
  assert.equal(w.sent.length, n);
  assert.equal(w.trip.phase, "onDesktop");
});

test("an approval takes the cat to the notch with the surprised emote, and the answer sends it back out to its spot", () => {
  const w = world();
  w.trip.dragOut({ x: 700, y: 400 });
  w.sent.length = 0;
  w.trip.alert(true);
  assert.equal(w.trip.phase, "retracting");
  assert.deepEqual(w.sent, [{ k: "fly", from: { x: 700, y: 400 }, to: NOTCH, dir: "in", emote: "surprised", delayMs: SURPRISE_MS }]);
  w.trip.flightDone();
  assert.equal(w.trip.phase, "atNotchForAlert");
  assert.deepEqual(w.sent.at(-1), { k: "hide" }, "docked: the notch shows the cat again");
  assert.equal(w.empty.at(-1), false);
  assert.equal(w.settings.on, true, "still out as far as Settings goes");
  w.trip.alert(false);
  assert.equal(w.trip.phase, "returning");
  assert.deepEqual(w.sent.at(-1), { k: "fly", from: NOTCH, to: { x: 700, y: 400 }, dir: "out" });
  w.trip.flightDone();
  assert.equal(w.trip.phase, "onDesktop");
});

test("an alert that clears mid-flight turns the cat around; one that comes mid-return turns it again", () => {
  const w = world();
  w.trip.dragOut({ x: 700, y: 400 });
  w.trip.alert(true);
  w.trip.alert(false);
  assert.equal(w.trip.phase, "returning");
  assert.equal(w.sent.at(-1).k, "turn");
  w.trip.alert(true);
  assert.equal(w.trip.phase, "retracting");
  assert.equal(w.sent.at(-1).k, "turn");
});

test("a send-home during an alert ends the trip at home, and an approval that lands while the cat is home takes nothing out", () => {
  const w = world();
  w.trip.dragOut({ x: 700, y: 400 });
  w.trip.alert(true);
  w.trip.flightDone();
  w.trip.sendHome();
  assert.equal(w.trip.phase, "home");
  assert.equal(w.settings.on, false);
  assert.equal(w.empty.at(-1), false);
  const n = w.sent.length;
  w.trip.alert(false); w.trip.alert(true);
  assert.equal(w.trip.phase, "home");
  assert.equal(w.sent.length, n, "an approval while the cat is home does not take it out");
});

test("a double-click flies the cat home, 'out' is cleared at once, and the landing hides the window and shows the notch cat", () => {
  const w = world();
  w.trip.dragOut({ x: 700, y: 400 });
  w.sent.length = 0;
  w.trip.sendHome();
  assert.equal(w.trip.phase, "flyingHome");
  assert.deepEqual(w.sent, [{ k: "fly", from: { x: 700, y: 400 }, to: NOTCH, dir: "in" }]);
  assert.equal(w.settings.on, false, "quitting mid-flight leaves the cat home");
  assert.equal(w.empty.at(-1), true, "the notch spot stays empty until the cat lands");
  w.trip.flightDone();
  assert.deepEqual([w.trip.phase, w.sent.at(-1), w.empty.at(-1)], ["home", { k: "hide" }, false]);
});

test("the switch flips the cat's trip: the stored 'out' says one thing and the phase another, and sync() takes the trip it asked for; a save of our own is not a request", () => {
  const w = world();
  assert.equal(w.trip.sync(), null);
  w.settings = { ...w.settings, on: true };
  w.trip.sync();
  assert.equal(w.trip.phase, "flyingOut");
  assert.equal(w.trip.sync(), null, "the machine stored on: true itself, so nothing is asked");
  w.settings = { ...w.settings, on: false };
  w.trip.sync();
  assert.equal(w.trip.phase, "flyingHome");
  w.settings = { ...w.settings, on: true };
  w.trip.sync();
  assert.equal(w.trip.phase, "flyingOut", "switched on again mid-flight: it turns around");
  assert.equal(w.sent.at(-1).k, "turn");
});

test("a cat that was out flies back out after the greeting, and a cat that was home does not", () => {
  const home = world();
  assert.equal(home.trip.launch().act, null);
  assert.equal(home.trip.phase, "home");
  const out = world();
  out.settings = { ...out.settings, on: true };
  out.trip.launch();
  assert.equal(out.trip.phase, "flyingOut");
  out.trip.launch();
  assert.equal(out.trip.phase, "flyingOut", "a second launch changes nothing");
});

test("the screens changed: the cat finds its spot again on the new arrangement, and the flight's desktop end follows", () => {
  const w = world();
  w.trip.dragOut({ x: 1400, y: 600 });
  w.screens = [{ frame: { x: 0, y: 0, w: 800, h: 600 }, visible: { x: 0, y: 0, w: 800, h: 600 }, main: true }];
  w.trip.screensChanged();
  assert.equal(w.trip.phase, "onDesktop");
  const s = w.sent.at(-1);
  assert.equal(s.k, "desktopEnd");
  assert.ok(s.spot.x <= 800 - 24 - 32 && s.spot.y <= 600 - 24 - 32, "back on the small screen, in its default spot");
  w.trip.alert(true);
  const n = w.sent.length;
  w.trip.screensChanged();
  assert.equal(w.trip.phase, "retracting");
  assert.equal(w.sent.length, n, "a screens change mid-retract: the machine ignores it, the window keeps flying");
});

test("a flight in the air follows the notch spot; nothing is sent when the cat is not flying", () => {
  const w = world();
  w.trip.notchMoved();
  assert.equal(w.sent.length, 0);
  w.trip.dragOut({ x: 700, y: 400 });
  w.sent.length = 0;
  w.trip.notchMoved();
  assert.equal(w.sent.length, 0, "on the desktop");
  w.trip.alert(true);
  w.sent.length = 0;
  w.notch = { x: 756, y: 58 };
  w.trip.notchMoved();
  assert.deepEqual(w.sent, [{ k: "notchEnd", spot: { x: 756, y: 58 } }]);
  w.trip.notchMoved();
  assert.equal(w.sent.length, 1, "only a change is sent");
  w.notch = NOTCH;
  w.trip.notchMoved();
  assert.deepEqual(w.sent.at(-1), { k: "notchEnd", spot: NOTCH }, "and it can move back");
});

test("only a change of the alert is an event, and an event that makes no sense changes nothing: no message, no save, no notch change", () => {
  const w = world();
  assert.equal(w.trip.alert(false), null);
  w.trip.alert(true);
  assert.equal(w.trip.alert(true), null);
  assert.equal(w.sent.length + w.saves + w.empty.length, 0, "an alert while home does nothing");
  for (const ev of [{ type: "flightDone" }, { type: "move", spot: { x: 1, y: 1 } }, { type: "bogus" }, null, 7]) {
    const r = w.trip.event(ev);
    assert.equal(r.act, null);
  }
  assert.equal(w.sent.length + w.saves + w.empty.length, 0);
});

test("every phase the trip can reach agrees with the contract: the notch is empty exactly where the cat is drawn, and 'on' is what the machine stored", () => {
  // Walk every event from every phase the trip reaches and compare the side effects with the phase's table row.
  const seen = new Set();
  const walk = (path) => {
    const w = world();
    for (const ev of path) w.trip.event(ev);
    const info = DESKTOP_PHASE_INFO[w.trip.phase];
    if (w.empty.length) assert.equal(w.empty.at(-1), info.notchEmpty, JSON.stringify(path));
    if (w.empty.length) assert.equal(w.settings.on, info.on, JSON.stringify(path));
    seen.add(w.trip.phase);
    return w;
  };
  const evs = [{ type: "toggle" }, { type: "sendHome" }, { type: "alertOn" }, { type: "alertOff" }, { type: "flightDone" }, { type: "dragOut", spot: { x: 700, y: 400 } }];
  const frontier = [[]];
  for (let depth = 0; depth < 5; depth++) for (const p of frontier.splice(0)) for (const ev of evs) { const q = [...p, ev]; walk(q); if (depth < 4) frontier.push(q); }
  assert.deepEqual([...seen].sort(), [...DESKTOP_PHASES].sort(), "every phase was reached");
  assert.equal(desktopStep("home", { type: "launch" }).act, "flyOut");
});

test("the island's own saves echo back and are not commands: a drop that places the cat is not followed by a trip home and back, and a send-home is not undone", () => {
  const w = echoWorld();
  w.trip.dragOut({ x: 700, y: 400 });
  assert.deepEqual(kinds(w), ["show"]);
  w.flush();
  assert.deepEqual([w.trip.phase, kinds(w), w.settings.on], ["onDesktop", ["show"], true], "no fly, no turn: every echo agrees with the phase");
  w.trip.move({ x: 300, y: 300 });
  w.flush();
  assert.deepEqual([w.trip.phase, kinds(w)], ["onDesktop", ["show", "show"]]);
  w.trip.sendHome();
  w.flush();
  assert.deepEqual([w.trip.phase, kinds(w), w.settings.on], ["flyingHome", ["show", "show", "fly"], false]);
  w.trip.flightDone();
  w.flush();
  assert.deepEqual([w.trip.phase, kinds(w).at(-1)], ["home", "hide"]);
  // The tray and the switch take the cat out the same way: one fly, and the echoes add nothing.
  const t = echoWorld();
  t.trip.toggle();
  t.flush();
  assert.deepEqual([t.trip.phase, kinds(t), t.settings.on], ["flyingOut", ["fly"], true]);
  t.trip.flightDone();
  t.trip.alert(true);
  t.flush();
  assert.deepEqual([t.trip.phase, kinds(t)], ["retracting", ["fly", "fly"]]);
});

// ── gestures ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

function pointer() {
  const p = { now: 0, timers: [], out: [] };
  p.g = new Gestures({
    set: (fn, ms) => { p.timers.push({ at: p.now + ms, fn, id: p.timers.length + 1 }); return p.timers.length; },
    clear: (id) => { const t = p.timers.find((x) => x.id === id); if (t) t.fn = null; },
    emit: (g) => p.out.push(g),
  });
  p.advance = (ms) => { p.now += ms; for (const t of p.timers) if (t.fn && t.at <= p.now) { const f = t.fn; t.fn = null; f(); } };
  return p;
}

test("a click acts after one double-click interval, so a double-click never also opens the island", () => {
  const p = pointer();
  p.g.press(10, 10); p.g.release();
  assert.deepEqual(p.out, []);
  p.advance(DOUBLE_MS - 1);
  assert.deepEqual(p.out, []);
  p.advance(1);
  assert.deepEqual(p.out, [{ k: "click" }]);
  p.out.length = 0;
  p.g.press(10, 10); p.g.release();
  p.advance(100);
  p.g.press(10, 10); p.g.release();
  p.advance(5000);
  assert.deepEqual(p.out, [{ k: "double" }], "a double-click, and no click after it");
});

test("a press that moves 4 px or more is a drag, reported in steps, and never a click; a wobble under 4 px is still a click", () => {
  const p = pointer();
  p.g.press(100, 100); p.g.move(102, 102); p.g.release();
  p.advance(DOUBLE_MS);
  assert.deepEqual(p.out, [{ k: "click" }]);
  p.out.length = 0;
  p.g.press(100, 100); p.g.move(100 + DRAG_PX - 0.1, 100); p.g.move(104, 100); p.g.move(110, 105); p.g.release();
  assert.deepEqual(p.out, [{ k: "dragStart" }, { k: "drag", dx: 4, dy: 0 }, { k: "drag", dx: 10, dy: 5 }, { k: "dragEnd" }], "each step is the pointer's distance from where it was pressed: the window follows it back to the press point");
  p.advance(5000);
  assert.equal(p.out.length, 4, "no click after a drag");
});

test("a drag cancels a click that was waiting, a cancel ends a drag, and a point that is not a number is ignored", () => {
  const p = pointer();
  p.g.press(1, 1); p.g.release();
  p.g.press(1, 1); p.g.move(50, 50);
  assert.deepEqual(p.out, [{ k: "dragStart" }, { k: "drag", dx: 49, dy: 49 }]);
  p.g.cancel();
  assert.equal(p.out.at(-1).k, "dragEnd");
  p.advance(5000);
  assert.equal(p.out.some((g) => g.k === "click" || g.k === "double"), false);
  const q = pointer();
  q.g.press(NaN, 1); q.g.move(Infinity, 1); q.g.release(); q.g.move(5, 5); q.g.release();
  q.advance(5000);
  assert.deepEqual(q.out, []);
});

test("a handler that cancels the press at dragStart (GNOME's native drag does) ends the drag cleanly: the move that started it does not throw", () => {
  const out = [];
  let g;
  g = new Gestures({ set: () => 1, clear: () => {}, emit: (e) => { out.push(e.k); if (e.k === "dragStart") g.cancel(); } });
  g.press(0, 0);
  assert.doesNotThrow(() => g.move(50, 50));
  assert.deepEqual(out, ["dragStart", "dragEnd"], "no drag step after the cancel");
  g.release();
  assert.deepEqual(out, ["dragStart", "dragEnd"]);
});

test("M2: a size change re-settles the cat for the new size: a Small cat at the edge is held clear of the edge when it becomes Large", () => {
  const w = world();
  w.settings = { ...w.settings, size: "small" };
  w.trip.dragOut({ x: 1480, y: 900 });
  const small = w.sent.at(-1).spot;
  w.settings = { ...w.settings, size: "large" };
  w.trip.screensChanged();
  const e = w.sent.at(-1);
  assert.equal(e.k, "desktopEnd");
  assert.ok(e.spot.x < small.x && e.spot.y < small.y, `a bigger cat sits further in: ${JSON.stringify(small)} -> ${JSON.stringify(e.spot)}`);
  assert.deepEqual(e.spot, spotFor(w.settings.spots, LAPTOP, "large"));
});
