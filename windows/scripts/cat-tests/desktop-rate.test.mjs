import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The frame-rate rule and the bench (sub-project H, spec §3), pinned by source where they need a browser.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("the body keeps to the contract's frame rate: desktopFps with every flag it knows, the cursor's distance, a kitten arriving or leaving as motion, and a hidden page at 0", () => {
  const body = source("desktop/body.ts");
  assert.match(body, /this\.gov\.setRate\(desktopFps\(\{/);
  assert.match(body, /phase: this\.flight \? "flyingOut" : this\.visible \|\| this\.carrying \? "onDesktop" : "home", hidden: document\.visibilityState === "hidden"( \|\| this\.away)?, dragging: this\.carrying \|\| this\.dragging,/);
  assert.match(body, /emote: now < this\.emoteUntil, kittenMotion: now < this\.kittenMotionUntil, dance: look\?\.dancing === true, asleep: look\?\.asleep === true, working: look\?\.working === true,/);
  assert.match(body, /\.\.\.\(c && at \? \{ cursorDist: Math\.hypot\(c\.x - at\.x, c\.y - at\.y\) \} : \{\}\),/, "no cursor, no distance");
  assert.match(body, /if \(sig !== this\.kittenSig\) \{ this\.kittenSig = sig; this\.kittenMotionUntil = now \+ KITTEN_MOTION_MS; \}/);
  assert.doesNotMatch(body, /DESKTOP_FPS/, "the rule is the contract's, not a copy");
});

test("the ?dev page has the alert flight as a strip of frames and the bench with the CPU of each rate", () => {
  const dev = source("cat/devdesktop.ts");
  for (const id of ["desktop-mock", "desktop-flight", "desktop-bench", "desktop-bench-run"]) assert.ok(dev.includes(`"${id}"`), id);
  assert.match(dev, /ms \* fps\) \/ 10/, "ms per frame times frames a second over ten is a percent of one core");
  assert.match(dev, /DESKTOP_FPS\.asleep, DESKTOP_FPS\.idle|pct\(DESKTOP_FPS\.asleep\)/);
});
