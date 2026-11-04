import test from "node:test";
import assert from "node:assert/strict";
import { labelGivesWay } from "../../src/views/titlefit.ts";
import { code } from "./util.mjs";

// The Claude Code card's title row, whole-or-nothing (task-fix-titlerow): the label is drawn whole or not at all. The numbers are the debug report's
// measurements (.superpowers/sdd/2026-10-17-p-tauri-projects/task-fix-titlerow-report.md): the row's content is 176 px, the name is 22 px natural, and a row
// that needs N px squeezes the name by max(0, N - 176). Text widths are not in the CSS, so only the layout numbers they rest on are pinned (below).

const CONTENT = 176, NAME = 22;
/** The name's shown width when a row needs `need` px: the name gives way first. */
const shown = (need) => NAME - Math.max(0, need - CONTENT);
/** The label is dropped for a row that needs `need` px. */
const dropped = (need) => labelGivesWay(NAME, shown(need));

test("the measured rows keep or drop the label as the report says", () => {
  assert.equal(dropped(152), false, "one capsule, no counter (the Mac's row b): the label is kept");
  assert.equal(dropped(174), false, "one capsule and 7/7: kept, by 2 px");
  assert.equal(dropped(172), false, "two capsules, no counter: kept");
  assert.equal(dropped(194), true, "two capsules and 7/7 (the picture): 18 px over, the label is dropped");
});

test("the half-pixel slack is the edge: 176.4 px is kept, 176.6 px is dropped", () => {
  assert.equal(dropped(176.4), false, "0.4 px over is within the slack");
  assert.equal(dropped(176.6), true, "0.6 px over is a cut");
});

test("the layout numbers under those measurements are the ones in the CSS", () => {
  const style = code("style.css"), pj = code("projects/projects.css"), views = code("views/projects.ts");
  // The title row is the card's .who: its padding is the cat's inset on the left and the jump's reserve on the right.
  assert.match(style, /\.who \{\s*padding: 0 36px 0 108px;/, "the .who row: 108 px cat inset, 36 px jump reserve");
  // The left column is 322 px; its card has a 1 px border each side, so the row is 320 px wide and its content is 320 - 108 - 36 = 176 px.
  assert.match(style, /\.overview > \.left \{\s*flex: 0 0 322px;\s*width: 322px;\s*\}/, "the left column is 322 px");
  assert.match(style, /\.card \{[^}]*border: 1px solid var\(--hairline\);/, "the card has a 1 px border");
  assert.match(style, /\* \{\s*box-sizing: border-box;/, "widths include padding and border, so the card's inner width is 320");
  assert.equal(322 - 2 * 1 - 108 - 36, CONTENT, "322 - 2 (border) - 108 - 36 is the 176 px content");
  // The capsule's metrics (the two capsules and the gap): the text width of "3" and "7/7" is not in the CSS, so only these are pinned.
  assert.match(pj, /\.pj-cap \{\s*display: inline-flex;\s*align-items: center;\s*gap: 4px;\s*flex: 0 0 auto;\s*margin-left: 2px;\s*\}/, "the capsule group: 4 px gap, 2 px left margin");
  assert.match(pj, /\.pj-capsule \{[^}]*min-width: 16px;[^}]*height: 14px;[^}]*padding: 0 5px;/, "a capsule: at least 16 px wide, 14 px high, 5 px side padding");
  // The chevron has no size of its own: it is the 16 px icon button, drawn with a 10 px icon.
  assert.match(views, /class: "icon-btn pj-chev"/, "the chevron is an icon button");
  assert.match(style, /\.icon-btn \{[^}]*width: 16px;[^}]*height: 16px;/, "the icon button is 16 px square");
  assert.match(views, /svg\(ICONS\.chevronDown, 10, \{ stroke: 2 \}\)/, "the chevron icon is 10 px");
  assert.match(pj, /\.int-head\.pj-fit b \{[^}]*text-overflow: ellipsis;/, "the name is the part that gives way");
});
