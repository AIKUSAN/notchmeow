import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the island page calls the wing's rules (island.ts, fsm.ts, style.css, desktop.ts), pinned as source text.
const read = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const island = read("island/island.ts"), fsm = read("island/fsm.ts"), css = read("style.css"), desktop = read("island/desktop.ts"), main = read("main.ts"), driver = read("island/wingdriver.ts"), rules = read("island/wing.ts");

test("the pointer feeds the rules from the cursor event, and only where the OS gives a global pointer", () => {
  assert.match(island, /if \(!this\.cursorPoll\) return this\.wing\.feed\(null, false\);/, "Wayland: the wings stay put");
  assert.match(island, /const zone = active \? this\.wingZone\(x, y\) : null;\s*this\.fsm\.pointerOnWing = zone !== null;\s*return this\.wing\.feed\(zone, active\);/);
  assert.match(island, /const wing = this\.feedWing\(x, y\);\s*const inIsland = this\.hitRectContains\(x, y\) && !wing\.passThrough;/, "the pointer on a folded wing is not on the island");
  assert.match(island, /return zoneOf\(wings\(this\.islandRect\(\), NOTCH_W, HIT_MARGIN\), x, y\);/, "the zones are the full island's, never the shrunk one");
  assert.match(main, /onEvent<\{ x: number; y: number; down\?: boolean \}>\("cursor", \(\{ x, y, down \}\) => island\.onCursor\(x, y, down\)\)/);
});

test("the alert list: everything that wants the island cancels the step-aside", () => {
  const m = /private wingActive\(\): boolean \{([\s\S]*?)\n  \}/.exec(island);
  assert.ok(m, "wingActive exists");
  for (const need of ["State.pendingApproval !== null", "this.fsm.held", "State.isPinned", "this.fsm.menuOpen", "State.fileCatch()", "this.dragOut.active", "this.desktop?.awayFromHome", "State.desktopNotchEmpty",
    'State.mode === "compact"', "this.greetingShown()", "this.press.active"]) assert.ok(m[1].includes(need), `wingActive looks at ${need}`);
  assert.match(desktop, /get awayFromHome\(\): boolean \{ return this\.trip\.phase !== "home"; \}/);
});

test("the swoosh, the fade and click-through follow the rules", () => {
  assert.match(island, /private swoosh = new Tracked\(0\);/);
  assert.match(island, /this\.swoosh\.springTo\(now\.faded \? 1 : 0, SPRING_RESPONSE, SPRING_DAMPING\);/);
  assert.match(island, /const w = swoosh === 0 \? full : widthAt\(full, NOTCH_W, swoosh\);/);
  assert.match(island, /this\.wing\.state\.faded && State\.mode === "compact" \? foldedHitRect\(viewportWidth\(\), hh, NOTCH_W, HIT_MARGIN\) : \{ x: \(viewportWidth\(\) - full\) \/ 2, y: 0, w: full, h: hh \}/);
  assert.match(island, /this\.swoosh\.animating \|\| this\.wingFade !== \(this\.wing\.state\.faded \? 0 : 1\)/, "the frame loop runs while the swoosh or the fade moves, and stops after");
  assert.match(island, /this\.islandEl\.style\.setProperty\("--nm-wing", String\(this\.wingFade\)\);/);
});

test("Open on hover: the pointer on a wing holds the dwell, and coming off a wing into the middle arms it again", () => {
  assert.match(fsm, /pointerOnWing = false;/);
  assert.match(fsm, /\|\| this\.held \|\| this\.menuOpen \|\| this\.pointerOnWing\) return;/);
  assert.match(fsm, /hoverResume\(\) \{/);
  assert.match(island, /if \(inIsland && this\.wasInIsland && wasOnWing && !this\.fsm\.pointerOnWing\) this\.fsm\.hoverResume\(\);/);
});

test("the style: opacity by filter, only while the fade is not at rest, and no transition of its own on the cats", () => {
  const start = css.indexOf("The wings step aside");
  assert.ok(start > 0, "the wing block exists");
  const block = css.slice(start, css.indexOf("}", css.indexOf("#island.wing-on #bot-glow", start)) + 1);
  assert.match(block, /#island\.wing-on #bot-canvas,[\s\S]*#island\.wing-on #shelf-badge \{\s*filter: opacity\(var\(--nm-wing, 1\)\);/);
  assert.match(block, /#island\.wing-on #bot-glow \{\s*filter: blur\(6px\) opacity\(var\(--nm-wing, 1\)\);/);
  assert.doesNotMatch(block, /transition/, "no transition is added to a canvas that other code hides");
});

test("it costs nothing of its own: one one-shot timer through the driver, no interval, no new frame loop", () => {
  assert.equal((island.match(/setInterval/g) ?? []).length, 0);
  assert.equal((island.match(/requestAnimationFrame/g) ?? []).length, 2);
  assert.doesNotMatch(rules, /setTimeout|setInterval|addEventListener|requestAnimationFrame/);
  assert.doesNotMatch(driver, /setInterval|requestAnimationFrame|addEventListener/);
  assert.match(driver, /this\.timer = this\.env\.set\(/);
});
