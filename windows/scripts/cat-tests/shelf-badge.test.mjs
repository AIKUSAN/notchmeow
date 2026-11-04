import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { badgeLabel, badgePlace, badgeShown, badgeTitle } from "../../src/shelf/badge.ts";
import { COMPACT_W, NOTCH_H } from "../../src/core/layout.ts";

// The compact badge, the tray item and Ask from a tile (G1). The badge's rule is pure; the island's wiring is pinned in its source.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const isl = source("island/island.ts");

test("the badge shows only while the island is compact and something is on the shelf: never hidden, never open, never over the greeting", () => {
  assert.equal(badgeShown("compact", 3, false), true);
  assert.equal(badgeShown("hidden", 3, false), false, "it never wakes a hidden island");
  assert.equal(badgeShown("expanded", 3, false), false);
  assert.equal(badgeShown("compact", 0, false), false);
  assert.equal(badgeShown("compact", 3, true), false);
});

test("it says the count up to nine and 9+ after, its tooltip says it in words, and it sits at the right end of the compact wing", () => {
  assert.deepEqual([0, 1, 9, 10, 30].map(badgeLabel), ["0", "1", "9", "9+", "9+"]);
  assert.equal(badgeTitle(1), "Shelf: 1 file");
  assert.equal(badgeTitle(12), "Shelf: 12 files");
  const p = badgePlace(COMPACT_W, NOTCH_H);
  assert.deepEqual(p, { left: COMPACT_W - 25, top: NOTCH_H / 2 - 8 });
  assert.ok(p.left >= 236 && p.left + 16 <= COMPACT_W - 7, "inside the right ear, past the 2x2 grid (which ends 25 px from the edge), clear of the island's corner");
});

test("the island only draws the badge: a press on it opens the shelf and nothing else, and drawing it never opens, reveals or expands the island", () => {
  assert.match(isl, /this\.shelfBadge\.addEventListener\("mousedown", \(e\) => e\.stopPropagation\(\)\);\s*this\.shelfBadge\.addEventListener\("click", \(e\) => \{ e\.stopPropagation\(\); this\.openShelf\(\); \}\);/);
  const draw = isl.slice(isl.indexOf("// The shelf's badge: a function of the mode"), isl.indexOf("syncMiniBotStates(State.tasks);"));
  assert.match(draw, /const showBadge = badgeShown\(State\.mode, State\.shelf\.count, greetingActive\) && !showWait;/, "the waiting count takes the place first (sub-project P)");
  assert.doesNotMatch(draw, /alert\(|reveal\(|expand\(|setView\(|fsm\.|forceHome|setMode/, "a function of the mode, never a cause of it");
  assert.match(isl, /this\.shelfBadge\.style\.pointerEvents = showBadge \? "auto" : "none";/, "it takes the mouse only while it is shown");
  assert.match(isl, /this\.miniGrid,\s*this\.shelfBadge,\s*this\.countdown,/);
});

test("the shelf opens from the tray item, the badge and a drop; opening it looks at the files, and a hidden island comes up on it", () => {
  assert.match(source("main.ts"), /case "shelf":\s*setPaused\(false\);\s*island\.openShelf\(\);\s*break;/);
  assert.match(isl, /openShelf\(\) \{\s*void State\.shelf\.refresh\(\);\s*this\.alert\("shelf"\);\s*\}/);
  const tray = fs.readFileSync(new URL("../../src-tauri/src/tray.rs", import.meta.url), "utf8");
  assert.match(tray, /MenuItem::with_id\(app, "shelf", "Shelf", true, None::<&str>\)\?;/);
  assert.match(tray, /Menu::with_items\(app, &\[&open, &shelf, &desktop, &sep1, &settings, &pause, &sep2, &quit\]\)/);
});

test("Ask from a tile is a drop on Ask without the drag: the drop view opens, the cat is waited for, the catch plays, and Rust ingests by id", () => {
  const ask = isl.slice(isl.indexOf("private askShelf(id: string) {"), isl.indexOf("/** Whether the OS has a global cursor"));
  assert.match(ask, /if \(!entry \|\| !State\.shelf\.canAsk\(id\)\) return;\s*UploadSeq\.enterZone\(USC\.REST_X, USC\.REST_Y\);\s*this\.uploadCanvas\.hover\(true\);\s*this\.setView\("upload"\);\s*this\.whenCatIsHere\(\(\) => this\.swallow\(entry\.name, \(\) => Bridge\.shelfAsk\(id\)\)\);/);
  assert.match(isl, /shelf: \{ ask: \(id\) => this\.askShelf\(id\),/);
  assert.match(isl, /void ingest\(path\)\s*\.then\(async \(file\) => \{/, "the same copy, chime and chat reset as a drop: only the source of the file differs");
  assert.doesNotMatch(source("core/bridge.ts").match(/shelfAsk:[^\n]*/)[0], /path/, "the bridge sends an id");
});
