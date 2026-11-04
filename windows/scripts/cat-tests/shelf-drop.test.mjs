import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The Ask and Shelf halves (G1) as the island wires them. The island needs the DOM and the bridge to run, so these are source pins; the rules they call are replayed in
// shelf-rules.test.mjs and shelf-dropflow.test.mjs, and the picture of the two halves is the checkpoint's.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const isl = source("island/island.ts");
const between = (s, a, b) => s.slice(s.indexOf(a), s.indexOf(b));

test("a drop on Ask is today's drop, line for line: the first file, then the catch waits for the desktop cat", () => {
  const drop = between(isl, 'case "drop": {', "/** Where the OS has no global cursor");
  assert.match(drop, /const plan = planDrop\(this\.zoneNow\(\), e\.paths\);/);
  assert.match(drop, /const path = plan\.path;\s*this\.whenCatIsHere\(\(\) => this\.swallow\(path\)\);/);
  assert.match(drop, /if \(plan\.kind === "none"\) \{\s*this\.setView\(State\.defaultView\(\)\);\s*return;\s*\}/, "no file: the same fall back as before");
  assert.match(isl, /private swallow\(path: string, ingest: \(path: string\) => Promise<DroppedFile> = \(p\) => Bridge\.ingestFile\(p\)\) \{\s*const name = path\.split/, "swallow still takes one path, and ingests it with Bridge.ingestFile unless told otherwise");
});

test("a drop on Shelf takes every file, skips the desktop cat's wait and the catch, takes a fresh drop token and stops the upload sequence", () => {
  const shelf = isl.match(/private shelfDrop\(paths: string\[\]\) \{[\s\S]*?\n  \}\n/)[0];
  assert.doesNotMatch(shelf, /whenCatIsHere|swallow|engine\.triggerEmote|uploadCanvas\.drop|Sound\.play/, "no wait, no catch, no chime");
  assert.match(shelf, /this\.catchTurn\+\+;\s*this\.dropCount\+\+;\s*this\.dropWaiting = false;\s*UploadSeq\.deactivate\(\);\s*this\.uploadCanvas\.hover\(false\);\s*this\.setView\("shelf"\);\s*void State\.shelf\.add\(paths\)\.catch\(\(\) => \{\s*console\.warn\("shelf add failed"\);\s*\}\);/);
  assert.match(isl, /if \(plan\.kind === "shelf"\) \{\s*this\.shelfDrop\(plan\.paths\);\s*return;\s*\}/);
});

test("the file alert ends with the drag: a drop or a leave clears the drag and the half, and fileCatch reads the drop flow, which the shelf view is not in", () => {
  assert.match(isl, /State\.fileDragOver = false;\s*State\.dropZone = null;\s*\/\/ The island deliberately stays open/, "leave");
  assert.match(isl, /State\.fileDragOver = false;\s*State\.dropZone = null;\s*if \(plan\.kind === "none"\)/, "drop");
  assert.match(isl, /State\.fileCatch = \(\) => State\.fileDragOver \|\| this\.dropWaiting \|\| this\.uploadActive;/, "unchanged");
  assert.match(isl, /const UPLOAD_VIEWS: ReadonlySet<IslandViewName> = new Set\(\["upload", "uploading", "choose"\]\);/, "the shelf view is not an upload view");
});

test("the halves are a layer over the drop canvas and change nothing of it: the canvas, the sequence and the upload views do not know the shelf", () => {
  for (const f of ["upload/canvas.ts", "upload/sequence.ts", "views/upload.ts"]) assert.doesNotMatch(source(f), /shelf/i, f);
  assert.match(isl, /this\.uploadCanvas\.el,\s*this\.zones\.el,\s*this\.contentEl,/, "the layer sits right over the canvas, under the header's content");
  assert.match(isl, /this\.zones\.sync\(uploadActive && State\.fileDragOver, State\.dropZone\);/, "only while files are dragged over the open drop view");
  const z = source("shelf/zones.ts");
  assert.doesNotMatch(z, /setInterval|setTimeout|requestAnimationFrame|addEventListener/, "it draws nothing by itself and takes no mouse");
  assert.match(fs.readFileSync(new URL("../../src/style.css", import.meta.url), "utf8"), /#shelf-zones \{[^}]*pointer-events: none;/);
});

test("the pointer's half follows the cursor poll while files are over the island, and is read again at the drop; where there is no global cursor the event's position is the pointer", () => {
  assert.match(isl, /UploadSeq\.updateCursor\(State\.mouseInIsland\.x, State\.mouseInIsland\.y\);\s*this\.trackZone\(\);/);
  assert.match(isl, /case "over": \{\s*this\.noteDragPosition\(e\.position\);\s*if \(State\.fileDragOver\) return;/);
  assert.match(isl, /private trackZone\(\) \{\s*const zone = State\.fileDragOver \? this\.zoneNow\(\) : null;\s*if \(zone === State\.dropZone\) return;/, "only a change is announced");
  assert.match(source("main.ts"), /island\.setCursorPoll\(boot \? boot\.cursorPoll : true\);/);
});

test("the shelf is a view of the island with a place of its own, not an upload view", async () => {
  const L = await import("../../src/core/layout.ts");
  assert.deepEqual(L.VIEW_LAYOUTS.shelf, { height: 176, botX: 46, botY: 108, botDiameter: 44, agentMode: "none" });
  assert.equal(L.islandSize("expanded", "shelf").h, 176);
  assert.match(source("views/views.ts"), /map\.set\("shelf", /);
});
