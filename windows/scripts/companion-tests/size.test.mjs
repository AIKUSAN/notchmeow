import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { PANEL_H, EXPANDED_CORNER, VIEW_LAYOUTS, chatPromptHeight, islandSize, sidekickHeight } from "../../src/core/layout.ts";

// The bigger chat and the taller island window (F3a-tauri, Task 8): the chat grows from 240 to 560 px like the Mac's ChatSizing, and the transparent panel is 600 tall to hold it.

test("the chat starts at 240 px, gains 40 px a message and stops at 560 (the Mac's ChatSizing)", () => {
  assert.deepEqual([0, 1, 6, 7, 100].map(chatPromptHeight), [240, 280, 480, 520, 560]);
  assert.equal(islandSize("expanded", "prompt", 8).h, 560);
});

test("the window is as tall in layout.ts as in island.rs, and holds the biggest chat under the island's corner", () => {
  const rs = fs.readFileSync(new URL("../../src-tauri/src/island.rs", import.meta.url), "utf8");
  const m = rs.match(/pub const PANEL_H: f64 = (\d+(?:\.\d+)?);/);
  assert.ok(m, "island.rs has pub const PANEL_H: f64");
  assert.equal(Number(m[1]), PANEL_H);
  assert.equal(PANEL_H, 600);
  assert.ok(PANEL_H >= 560 + EXPANDED_CORNER, "the chat and the corner fit");
});

test("every view fits the window, whatever its content makes it grow to", () => {
  for (const [name, l] of Object.entries(VIEW_LAYOUTS)) assert.ok(l.height <= PANEL_H, name);
  assert.ok(sidekickHeight(100) <= PANEL_H);
  assert.ok(chatPromptHeight(1e6) <= PANEL_H);
});

test("the other views keep their heights: the taller window moves nothing", () => {
  assert.equal(islandSize("expanded", "overview").h, 160);
  assert.equal(islandSize("expanded", "mail").h, 240);
  assert.equal(islandSize("compact", "prompt").h, 32);
});
