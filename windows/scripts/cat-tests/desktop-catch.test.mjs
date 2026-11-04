import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DESKTOP_CATCH_WAIT_MS, DESKTOP_PHASES, DESKTOP_PHASE_INFO, defaultDesktopSettings, desktopAlert, desktopCatchReady } from "../../src/cat/desktop.ts";
import { DesktopTrip } from "../../src/cat/desktoptrip.ts";
import { State } from "../../src/core/state.ts";
import { load } from "./util.mjs";

// The file catch (fixes after H): a file on its way into the island is an alert to the desktop cat. The rules are the contract's (tests/fixtures/cat/desktop-cases.json), the island feeds
// `fileCatch` from the drop flow, and the catch canvas draws no cat of its own while the desktop cat is out.
const fx = load("desktop-cases.json");
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const LAPTOP = [{ frame: { x: 0, y: 0, w: 1512, h: 982 }, visible: { x: 0, y: 37, w: 1512, h: 875 }, main: true }];
const NOTCH = { x: 756, y: 16 };
function world() {
  const w = { settings: defaultDesktopSettings(), sent: [], empty: [] };
  w.env = { body: (m) => w.sent.push(m), notchSpot: () => NOTCH, screens: () => LAPTOP, settings: () => w.settings, save: (s) => { w.settings = s; }, notchEmpty: (e) => w.empty.push(e) };
  w.trip = new DesktopTrip(w.env);
  return w;
}

test("the wait, desktopAlert and desktopCatchReady are the fixture's", () => {
  assert.equal(DESKTOP_CATCH_WAIT_MS, fx.catchWaitMs);
  for (const c of fx.alertCases) assert.equal(desktopAlert(c.input), c.out, c.name);
  for (const c of fx.catchReady) assert.equal(desktopCatchReady(c.phase), c.out, JSON.stringify(c.phase));
  assert.deepEqual(DESKTOP_PHASES.filter((p) => desktopCatchReady(p)), ["home", "atNotchForAlert"]);
  for (const p of DESKTOP_PHASES) assert.equal(desktopCatchReady(p), !DESKTOP_PHASE_INFO[p].drawn, `${p}: ready exactly when the desktop window does not draw the cat`);
  assert.equal(desktopAlert(Object.freeze({ fileCatch: true })), true, "a frozen input is read, not changed");
});

test("a file catch through the trip: the cat flies in surprised, the notch holds the cat for the catch, an approval keeps it there, and it flies back out when both are clear", () => {
  const w = world();
  w.trip.dragOut({ x: 400, y: 300 });
  assert.equal(w.trip.phase, "onDesktop");
  w.sent.length = 0;
  w.trip.alert(desktopAlert({ fileCatch: true }));
  assert.equal(w.trip.phase, "retracting");
  assert.deepEqual(w.sent.map((m) => [m.k, m.dir, m.emote]), [["fly", "in", "surprised"]]);
  assert.equal(w.empty.at(-1), true, "the notch's spot stays empty while the cat flies");
  w.trip.flightDone();
  assert.equal(w.trip.phase, "atNotchForAlert");
  assert.equal(w.sent.at(-1).k, "hide", "the desktop window gives the cat up: the catch's cat at the notch is the only one");
  assert.equal(w.empty.at(-1), false, "and the notch's spot holds the cat, so the island may draw it");
  assert.equal(desktopCatchReady(w.trip.phase), true);
  const n = w.sent.length;
  assert.equal(w.trip.alert(desktopAlert({ fileCatch: false, approval: true })), null, "the drop flow ends while an approval waits: the alert stays on");
  assert.equal(w.sent.length, n);
  w.trip.alert(desktopAlert({ fileCatch: false, approval: false }));
  assert.equal(w.trip.phase, "returning");
  assert.deepEqual([w.sent.at(-1).k, w.sent.at(-1).dir], ["fly", "out"]);
  w.trip.flightDone();
  assert.equal(w.trip.phase, "onDesktop");
});

test("with the cat at home a file catch changes nothing: no message, no save, no change of the notch's spot", () => {
  const w = world();
  w.trip.alert(desktopAlert({ fileCatch: true }));
  w.trip.alert(desktopAlert({ fileCatch: false }));
  assert.equal(w.trip.phase, "home");
  assert.equal(w.sent.length + w.empty.length, 0);
  assert.equal(w.settings.on, false);
});

test("State.fileCatch is, until the island says otherwise, the drag being over the island", () => {
  State.fileDragOver = false;
  assert.equal(State.fileCatch(), false);
  State.fileDragOver = true;
  assert.equal(State.fileCatch(), true);
  State.fileDragOver = false;
});

test("the island feeds the drop flow to the alert rule, the catch canvas draws no cat while the cat is out, and a drop waits for the cat with a bounded chain of timeouts", () => {
  const b = source("island/desktop.ts");
  assert.match(b, /this\.trip\.alert\(desktopAlert\(\{ approval: State\.attentionNeeded, fileCatch: State\.fileCatch\(\), transferOffer: State\.linkOfferPending \}\)\);\s*this\.trip\.notchMoved\(\);/);
  const isl = source("island/island.ts");
  assert.match(isl, /State\.fileCatch = \(\) => State\.fileDragOver \|\| this\.dropWaiting \|\| this\.uploadActive;/, "the drag, a drop that waits for the cat, or the drop flow on screen");
  assert.match(isl, /this\.whenCatIsHere\(\(\) => this\.swallow\(path\)\);/, "the catch starts when the cat is here");
  const wait = isl.slice(isl.indexOf("private whenCatIsHere"), isl.indexOf("private swallow"));
  assert.match(wait, /State\.desktopNotchEmpty && performance\.now\(\) - t0 < DESKTOP_CATCH_WAIT_MS/, "bounded by the contract's wait");
  assert.doesNotMatch(wait, /setInterval|requestAnimationFrame/, "no interval and no frame loop: a chain of timeouts that lasts as long as one drop");
  assert.match(isl, /import \{ DESKTOP_CATCH_WAIT_MS \} from "\.\.\/cat\/desktop";/);
  const canvas = source("upload/canvas.ts");
  assert.match(canvas, /if \(!f\.fileVisible\) this\.cat\.fileArrived\(\);\s*\/\/[^\n]*\n\s*if \(State\.desktopNotchEmpty\) return;/, "the file still arrives; the cat is not drawn while it is on the desktop");
  assert.match(source("cat/devdesktop.ts"), /so does a file dragged onto the notch/);
});

test("a dropped file's catch runs only for the latest drop and only while the drop flow is open after a wait; a home cat runs the drop at once; a latest drop whose flow closed clears its drag state and notifies (a source pin: the island needs the DOM and the bridge to run)", () => {
  const isl = source("island/island.ts");
  assert.match(isl, /private catchTurn = 0;/, "a token of its own: the drop count moves only when the catch runs, so it cannot tell two waiting drops apart");
  const wait = isl.slice(isl.indexOf("private whenCatIsHere"), isl.indexOf("private swallow"));
  assert.match(wait, /const turn = \+\+this\.catchTurn;/, "the token is taken at the drop");
  assert.match(wait, /waited = true;\s*window\.setTimeout\(wait, 50\);/, "the flag is set when the wait's chain is entered");
  assert.match(wait, /const latest = turn === this\.catchTurn;\s*if \(latest\) this\.dropWaiting = false;/, "a superseded drop never clears the newer drop's alert");
  assert.match(wait, /if \(!waited \|\| \(latest && this\.uploadActive\)\) \{\s*run\(\);\s*return;\s*\}/, "the home cat runs at once; after a wait, only the latest drop with its flow still open runs");
  assert.match(wait, /if \(latest\) \{\s*State\.fileDragOver = false;\s*State\.notify\(\);\s*\}/, "the latest drop whose flow closed clears its drag state and notifies, as the Mac does");
});
