import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DRAG_PX } from "../../src/cat/gestures.ts";
import { PressDrag } from "../../src/cat/pressdrag.ts";
import { PAIR, PANEL_W } from "../../src/core/layout.ts";
import { defaultWorld } from "../../src/cat/desktopview.ts";
import { islandToSpot, notchCatLocal, spotToIsland } from "../../src/core/notchspot.ts";
import { near } from "./util.mjs";

// The island's half of the desktop cat (sub-project H): the notch spot, the press on the big cat that is a click or a drag, and the seams the island's page and the desktop page are
// wired by, pinned by source (they need a browser).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const rust = (rel) => fs.readFileSync(new URL(`../../src-tauri/${rel}`, import.meta.url), "utf8");
const root = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("the notch spot: the compact cat is at 40 in a 288 island, the pair's first at 30, and a hidden island counts as compact", () => {
  near(notchCatLocal("compact", "overview", false).x, (PANEL_W - 288) / 2 + 40);
  assert.equal(notchCatLocal("compact", "overview", false).y, 16);
  near(notchCatLocal("hidden", "overview", false).x, notchCatLocal("compact", "overview", false).x);
  near(notchCatLocal("compact", "overview", true).x, (PANEL_W - 288) / 2 + PAIR.compact.x1);
  const open = notchCatLocal("expanded", "approval", false);
  assert.ok(open.x > 100 && open.x < 300 && open.y > 20 && open.y < 140, `the open island's cat is at ${JSON.stringify(open)}`);
  assert.notDeepEqual(open, notchCatLocal("compact", "approval", false), "the notch spot moves when the island opens: a flight in the air follows it");
});

test("the island window's px are points on the desktop, and back: the middle of the window is the middle of the island's screen", () => {
  const w = { ...defaultWorld(), island: { x: 0, y: 0, w: 1512, h: 982 }, islandK: 1 };
  assert.deepEqual(islandToSpot(w, PANEL_W / 2, 16), { x: 756, y: 16 });
  assert.deepEqual(islandToSpot(w, PANEL_W / 2 - 100, 40), { x: 656, y: 40 });
  const second = { ...w, island: { x: 1512, y: -100, w: 2560, h: 1440 }, islandK: 1.5 };
  assert.deepEqual(islandToSpot(second, PANEL_W / 2, 0), { x: 1512 + 1280, y: -100 });
  assert.deepEqual(islandToSpot(second, PANEL_W / 2 + 10, 10), { x: 1512 + 1280 + 15, y: -100 + 15 }, "one px of an island on a screen with another scale is islandK points");
  for (const world of [w, second]) for (const p of [{ x: 10, y: 5 }, { x: 360, y: 16 }, { x: 700, y: 300 }]) {
    const s = islandToSpot(world, p.x, p.y), b = spotToIsland(world, s);
    near(b.x, p.x); near(b.y, p.y);
  }
});

test("a press on the big cat is a click when it never moves 4 px and a drag when it does; a drag never clicks, and a press that is not a number is no press", () => {
  const p = new PressDrag();
  assert.deepEqual([p.move(1, 1), p.release()], [null, null], "nothing is pressed");
  p.press(100, 100);
  assert.deepEqual([p.move(102, 101), p.move(100, 103), p.dragging], [null, null, false]);
  assert.equal(p.release(), "click");
  assert.equal(p.release(), null);
  p.press(100, 100);
  assert.equal(p.move(100 + DRAG_PX, 100), "start");
  assert.deepEqual([p.move(200, 200), p.move(100, 100), p.dragging], ["drag", "drag", true], "once started it is a drag, even back at the press point");
  assert.equal(p.release(), "drop");
  p.press(NaN, 1);
  assert.deepEqual([p.active, p.move(50, 50), p.release()], [false, null, null]);
  p.press(1, 1); p.cancel();
  assert.deepEqual([p.active, p.release()], [false, null]);
  p.press(0, 0);
  assert.equal(p.move(NaN, 9), null, "a point that is not a number moves nothing");
});

test("the island: a press on the big cat is a click or a drag decided when the button comes up, the notch draws nothing of a cat that has left, cat 2 and the pills stay", () => {
  const i = source("island/island.ts");
  assert.match(i, /this\.desktop\?\.canCarry && !State\.desktopNotchEmpty && State\.mode !== "hidden" && !this\.greetingShown\(\) && !this\.uploadActive && this\.isBotHit\(x, y\)/);
  assert.match(i, /this\.pressAction = \(\) => this\.pressed\(x, y\);/);
  assert.match(i, /window\.addEventListener\("mousemove", \(e\) => \(\(e\.buttons & 1\) === 0 \? this\.carryUp\(e\.clientX, e\.clientY\) : this\.carryMove\(e\.clientX, e\.clientY\)\)\);\s*window\.addEventListener\("mouseup", \(e\) => this\.carryUp\(e\.clientX, e\.clientY\)\);/, "a move with the primary button up is the release, once");
  assert.match(i, /this\.botCanvas\.style\.opacity = visible && !State\.desktopNotchEmpty \? "1" : "0";/);
  assert.match(i, /this\.pairShown = pair !== null && visible;/, "cat 2 is drawn whether the big cat is out or not");
  assert.match(i, /if \(!State\.desktopNotchEmpty\) this\.drawBot\(dt\);\s*if \(this\.pairShown\) this\.drawBot2\(dt\);/);
  assert.match(i, /const big = shown && cast\.big\.pill && !State\.desktopNotchEmpty \? State\.kittenView\(cast\.big\.pill, now\) : \[\]/);
  assert.match(i, /&& !this\.uploadActive && !State\.desktopNotchEmpty\) \{\s*const d = p\.diameter;/, "no glow for a cat that is not there");
  assert.match(i, /this\.greeting\.onComplete = \(\) => \{ this\.fsm\.greetComplete\(\); this\.desktop\?\.afterGreeting\(\); \};/);
  assert.match(i, /open: \(\) => this\.alert\(State\.defaultView\(\)\),/, "a click on the desktop cat opens the island the way the tray's Open does");
});

test("main.ts makes the brain after the settings are loaded, starts it before the greeting, and tells it when the settings changed", () => {
  const m = source("main.ts");
  assert.match(m, /const desktop = new DesktopBrain\(island\.desktopHost\(\)\);\s*island\.attachDesktop\(desktop\);/);
  assert.ok(m.indexOf("State.giveCoats();") < m.indexOf("new DesktopBrain"), "after the coats");
  assert.ok(m.indexOf("await desktop.start();") < m.indexOf("island.launch();"), "before the launch greeting");
  assert.match(m, /void refreshConfigured\(\);\s*desktop\.settingsChanged\(\);/);
});

test("the brain sends a look before the first show or fly, sends only a change, and the desktop window's page runs nothing it does not need", () => {
  const b = source("island/desktop.ts");
  assert.match(b, /if \(m\.k === "show" \|\| m\.k === "fly"\) this\.sendLook\(true\);/);
  assert.match(b, /if \(!force && key === this\.last\) return;/);
  assert.match(b, /get canCarry\(\): boolean \{ return this\.trip\.phase === "home"; \}/);
  assert.doesNotMatch(b, /setInterval|setTimeout|requestAnimationFrame/, "the brain runs no timer of its own");
  const body = source("desktop/body.ts");
  assert.doesNotMatch(body, /setInterval/);
  assert.equal(body.match(/requestAnimationFrame/g).length, 1, "the governor's frame callback is the only one");
  assert.match(body, /this\.cv\.addEventListener\("pointerdown"/);
  assert.match(body, /document\.addEventListener\("visibilitychange", \(\) => this\.rate\(\)\);/);
  assert.match(body, /if \(!this\.world\.positioned\) \{ void Bridge\.desktopNativeDrag\(\); this\.gest\.cancel\(\); break; \}/, "where the system moves windows (GNOME) it drags the window");
});

test("fix round 1: a desktop cat put down on the notch flies home from the drop point, an empty big-cat spot is not slapped, only the primary button carries, a settings change waits for the screens", () => {
  const b = source("island/desktop.ts"), i = source("island/island.ts");
  // A: the move of a cat released over the notch is the contract's sendHome, started at the drop point; anywhere else it is a move.
  assert.match(b, /const s = spotOf\(m\.spot\), p = s && spotToIsland\(this\.world, s\);\s*if \(s && p && this\.host\.overNotch\(p\.x, p\.y\)\) \{\s*this\.homeFrom = s;\s*try \{ this\.trip\.sendHome\(\); \} finally \{ this\.homeFrom = null; \}\s*\} else this\.trip\.move\(m\.spot\);/);
  assert.match(b, /this\.homeFrom && m\.k === "fly" && m\.dir === "in" \? \{ \.\.\.m, from: this\.homeFrom \} : m/, "the flight home starts at the drop point, not at the spot before the drag");
  assert.match(b, /overNotch\(x: number, y: number\): boolean;/);
  assert.match(i, /overNotch: \(x, y\) => this\.overNotch\(x, y\),/);
  assert.match(i, /this\.desktop\?\.carryEnd\(x, y, this\.overNotch\(x, y\)\);/, "the carried cat and the desktop cat share one test for the notch");
  assert.match(i, /private overNotch\(x: number, y: number\): boolean \{\s*const rect = this\.islandRect\(\);\s*return x >= rect\.x - HIT_MARGIN && x <= rect\.x \+ rect\.w \+ HIT_MARGIN && y >= rect\.y - HIT_MARGIN && y <= rect\.y \+ rect\.h \+ HIT_MARGIN;/);
  // the carried big cat dropped on the notch still goes straight back (the cat never left it): carryEnd is unchanged
  assert.match(b, /const r = onNotch \? null : this\.trip\.dragOut\(islandToSpot\(this\.world, x, y\)\);/);
  // B: no slap at the empty spot of a cat that is out, decided inside pressed() only
  assert.match(i, /if \(hit === 1 && !State\.desktopNotchEmpty\) \{\s*this\.cancelBotHover\(\);\s*this\.engine\.slap\(\);/);
  // C: the primary button only starts a press that can become a carry
  assert.match(i, /if \(e\.button === 0 && this\.desktop\?\.canCarry && !State\.desktopNotchEmpty/);
  // D: a settings change before the screens are known waits and is applied when start() is through
  assert.match(b, /if \(!this\.started\) \{ this\.changedEarly = true; return; \}/);
  assert.match(b, /State\.subscribe\(\(\) => this\.changed\(\)\);\s*this\.started = true;\s*if \(this\.changedEarly\) this\.settingsChanged\(\);/);
});

test("I2: a cat that was out flies back out when the launch greeting is left any way at all, not only when it runs to its end", async () => {
  const i = source("island/island.ts");
  // every exit from the greeting is an fsm transition whose `from` is "hello": the greeting's own onComplete fires only for an undisturbed run
  assert.match(i, /this\.greeting\.start\(State\.cast\.greeting, State\.outfit\);\s*break;\s*\}\s*\/\/ The launch greeting is over, however it ended[^\n]*\n[^\n]*\n\s*if \(from === "hello"\) this\.desktop\?\.afterGreeting\(\);\s*State\.notify\(\);/, "after the mode is set, so the notch spot is the one the island has now");
  assert.match(i, /this\.greeting\.onComplete = \(\) => \{ this\.fsm\.greetComplete\(\); this\.desktop\?\.afterGreeting\(\); \};/, "the undisturbed run still takes the cat out at the greeting's end: launch() is a no-op the second time");
  // ...and the fsm really does report every way out of "hello" with from === "hello"
  const timers = [];
  globalThis.window = { setTimeout: (fn) => { timers.push(fn); return timers.length; }, clearTimeout: () => {} };
  const { IslandStateMachine } = await import("../../src/island/fsm.ts");
  const exits = { mouseLeft: (f) => f.mouseLeft(), forceHome: (f) => f.forceHome(), forceHidden: (f) => f.forceHidden(), forcePetit: (f) => f.forcePetit(), greetEnd: (f) => { f.greetComplete(); timers.pop()(); } };
  for (const [name, leave] of Object.entries(exits)) {
    const f = new IslandStateMachine(), seen = [];
    f.onTransition = (from, to) => seen.push([from, to]);
    f.launch();
    leave(f);
    assert.deepEqual(seen[0], ["hidden", "hello"]);
    assert.equal(seen[1]?.[0], "hello", `${name} leaves the greeting with from === "hello"`);
    assert.notEqual(f.state, "hello");
  }
  delete globalThis.window;
});

test("I5: the empty big-cat spot of a cat that is out is not hovered: no hover sound, no love", () => {
  const i = source("island/island.ts");
  assert.match(i, /const overBot = State\.mode === "expanded" && State\.stateOverride == null && !State\.desktopNotchEmpty && this\.isBotHit\(x, y\);\s*if \(overBot && !this\.botHovering\) this\.botHoverIn\(x, y\);\s*if \(!overBot && this\.botHovering\) this\.cancelBotHover\(\);/, "a hover that was running when the cat left is cancelled by the same line");
});

test("I3: the world is looked at again before the cat takes a trip out, when it is carried out, and by the body when it shows, flies or re-settles", () => {
  const b = source("island/desktop.ts"), m = source("main.ts"), body = source("desktop/body.ts");
  // the tray's item: refresh, then toggle
  assert.match(b, /async toggle\(\): Promise<void> \{\s*await this\.refresh\(\);\s*this\.trip\.toggle\(\);\s*\}/);
  assert.match(m, /case "desktop":\s*void desktop\.toggle\(\);/);
  assert.doesNotMatch(m, /desktop\.trip\.toggle/, "no trip out of the tray without a fresh world");
  // the switch: the screens first when a trip is due, then the trip; with nothing due, no round trip
  assert.match(b, /const act = \(\) => \{ this\.trip\.sync\(\); if \(DESKTOP_PHASE_INFO\[this\.trip\.phase\]\.drawn\) this\.sendLook\(true\); \};\s*\/\/[^\n]*\n\s*if \(State\.settings\.cat\.desktop\.on !== DESKTOP_PHASE_INFO\[this\.trip\.phase\]\.on\) void this\.refresh\(\)\.then\(act\);\s*else act\(\);/);
  // the carry: a world from before an undock must not turn pointer positions into spots
  assert.match(b, /carryStart\(\): void \{\s*\/\/[^\n]*\n\s*void this\.refresh\(\);\s*this\.carrying = true;/);
  // a failure keeps the old world and is no unhandled rejection (Bridge.call returns null)
  assert.match(b, /if \(w && Array\.isArray\(w\.screens\)\) this\.world = w;/);
  // the body: its own world (kittenSide, k) is asked for again on show, fly and desktopEnd, one question at a time
  assert.match(body, /case "show":\s*this\.refreshWorld\(\);/);
  assert.match(body, /case "fly": \{\s*this\.refreshWorld\(\);/);
  assert.match(body, /case "desktopEnd":\s*this\.refreshWorld\(\);/);
  assert.match(body, /if \(this\.refreshing\) return;\s*this\.refreshing = true;\s*void Bridge\.desktopScreens\(\)\.then\(\(w\) => \{\s*if \(w && Array\.isArray\(w\.screens\)\) \{ this\.world = w; this\.relayout\(\); \}\s*\}\)\.catch\(\(\) => \{\}\)\.finally\(\(\) => \{ this\.refreshing = false; \}\);/);
});

test("M2 and M3: a size change settles the cat's spot for the new size; a screen change of the island moves the notch end of a flight", () => {
  const b = source("island/desktop.ts"), m = source("main.ts");
  assert.match(b, /State\.settings\.cat = withDesktopSize\(State\.settings\.cat, m\.item\);\s*void Bridge\.saveSettings\(State\.settings\);\s*this\.sendLook\(true\);\s*\/\/[^\n]*\n\s*this\.trip\.screensChanged\(\);/);
  assert.match(b, /screenChanged\(\): void \{ void this\.refresh\(\)\.then\(\(\) => this\.trip\.notchMoved\(\)\); \}/);
  assert.match(m, /await onEvent<null>\("screen-changed", async \(\) => \{\s*await checkZoom\(\);\s*void Bridge\.reposition\(\);\s*desktop\.screenChanged\(\);\s*\}\);/);
});

test("M5, M6, M8 and M1: the body asks for no cursor where there is none, builds its menu once, lets go of a lost capture, and a flight in begins where the cat is", () => {
  const body = source("desktop/body.ts");
  // M5: Linux reads no cursor at all (cursor_physical is None): no question 5-20 times a second
  assert.match(body, /this\.cursorPoll = boot\.cursorPoll !== false;/);
  assert.match(body, /if \(!this\.cursorPoll \|\| this\.cursorAsked \|\| this\.flight \|\| this\.carrying \|\| this\.dragging \|\| this\.away \|\| this\.look\?\.asleep\) return;/);
  // M6: the native menu's items are built once; a right-click only moves the tick
  assert.match(body, /this\.menuParts \?\?= this\.buildMenu\(\);/);
  assert.match(body, /parts\.sizes\.map\(\(c, i\) => c\.setChecked\(DESKTOP_SIZE_IDS\[i\] === size\)\)/);
  const built = body.slice(body.indexOf("private async buildMenu()"));
  assert.equal(body.match(/\bMenuItem\.new\(|CheckMenuItem\.new\(|Submenu\.new\(/g).length, built.match(/\bMenuItem\.new\(|CheckMenuItem\.new\(|Submenu\.new\(/g).length, "the items are made in buildMenu only");
  assert.equal(body.match(/Menu\.new\(/g).length, 1);
  // M8: a capture that ends without a pointerup cancels the press, like pointercancel does
  assert.match(body, /addEventListener\("pointercancel", \(\) => this\.gest\.cancel\(\)\);[^\n]*\n[^\n]*\n\s*this\.cv\.addEventListener\("lostpointercapture", \(\) => this\.gest\.cancel\(\)\);/);
  // M1: an alert or Send home in the hand: the drag ends, the flight begins at the cat's own place; a press is not a drag while the cat flies
  assert.match(body, /if \(this\.dragging\) \{ this\.dragging = false; void Bridge\.desktopDrag\(false\); this\.gest\.cancel\(\); \}\s*const from = m\.dir === "in" && this\.visible && this\.spot \? this\.spot : m\.from;\s*this\.present\(from\);\s*this\.flight = new DesktopFlight\(from, m\.to,/);
  assert.match(body, /case "dragStart":\s*\/\/[^\n]*\n\s*if \(this\.flight\) break;/);
});
