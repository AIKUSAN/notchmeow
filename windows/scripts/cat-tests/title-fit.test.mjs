import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { labelGivesWay } from "../../src/views/titlefit.ts";

// The active session row's title: the tool label is whole beside the name or not drawn (the Mac's ProjectsTitleFit, commit 13a54a7c).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("a name cut short with the label beside it gives the label way; a name that fits whole keeps it", () => {
  assert.equal(labelGivesWay(201, 67), true, "a long name is cut to 67 pt of 201 pt: the label goes");
  assert.equal(labelGivesWay(201, 0), true, "a name squeezed to nothing: the label goes");
  assert.equal(labelGivesWay(34, 34), false, "a short name with room for the label keeps it");
  assert.equal(labelGivesWay(67, 67), false, "a name exactly fitting keeps the label");
  assert.equal(labelGivesWay(67.4, 67), false, "half a pixel of rounding is not a cut");
  assert.equal(labelGivesWay(67.6, 67), true, "a whole pixel cut is a cut");
});

test("the active row drops the label when the name is cut, and measures after the row is laid out", () => {
  const views = source("views/views.ts");
  assert.match(views, /import \{ labelGivesWay \} from "\.\/titlefit\.ts";/);
  const active = views.slice(views.indexOf("if (task && sessionActive) {"), views.indexOf("} else if (task) {"));
  assert.match(active, /const nameEl = h\("span", \{ class: "name", text: task\.name \}\);/);
  assert.match(active, /const toolEl = h\("span", \{ class: "tool"/);
  assert.match(active, /who\.append\(\s*dot\(task\.color, 7\),\s*nameEl,\s*toolEl,?\s*\);/);
  assert.match(active, /if \(labelGivesWay\(nameEl\.scrollWidth, nameEl\.clientWidth\)\) toolEl\.remove\(\);/);
  assert.ok(active.indexOf("toolEl.remove()") > active.indexOf("who.append("), "the check comes after the row is built");
});

test("the label never shrinks, so the name is the only part that gives way; the other rows are unchanged", () => {
  const css = source("style.css");
  assert.match(css, /\.who \.tool \{\s*font: 400 11px var\(--font\);\s*color: var\(--dim-2\);\s*white-space: nowrap;\s*flex: 0 0 auto;\s*\}/);
  const views = source("views/views.ts");
  assert.equal(views.split('class: "tool"').length - 1, 1, "only the active row has the label span; the agent cards' rows (agentWho) have none");
  assert.match(views, /function agentWho\(task: AgentTask \| null, label: string\): HTMLElement \{/);
});
