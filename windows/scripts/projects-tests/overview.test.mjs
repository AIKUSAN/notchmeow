import test from "node:test";
import assert from "node:assert/strict";
import { code } from "./util.mjs";

// The Claude-only card, the count capsule and chevron, and the section of the overview (Task 6 of P-tauri): the shipped overview's branches, the label rule, and the
// pins that keep every shipped rule as it is.

const v = code("views/views.ts"), ov = v.slice(v.indexOf("function buildOverview"), v.indexOf("function buildAgentPill"));

test("the Claude-only card takes the two cards only when the frame uses projects, and gives them back whole", () => {
  assert.match(ov, /const frame = State\.projectsNow\(\);/);
  assert.match(ov, /if \(frame\.usesProjects\) \{/);
  assert.match(ov, /mode = null;\s*cardKey = "";\s*pillIds = "";/, "leaving it rebuilds the shipped cards");
  assert.match(ov, /if \(frame\.usesProjects\) \{[\s\S]*?jump\.style\.display = "none";[\s\S]*?return;/, "the shipped ↗ hides while the big card draws its own");
});

test("the capsule and chevron go in the Claude Code card's title row, active or idle, only with frame.chevron; the label rule holds", () => {
  const active = ov.slice(ov.indexOf("if (task && sessionActive) {"), ov.indexOf("} else if (task) {"));
  assert.match(active, /who\.append\(dot\(task\.color, 7\), nameEl, toolEl\);\s*if \(frame\.chevron\) who\.append\(cap\.el\);/);
  assert.ok(active.indexOf("who.append(cap.el)") < active.indexOf("labelGivesWay("), "measured after the capsule is in the row");
  assert.match(ov, /head\.classList\.toggle\("pj-fit", fit\);/);
  assert.match(ov, /if \(fit\) \{\s*const name = head\.querySelector\("b"\) as HTMLElement;\s*if \(labelGivesWay\(name\.scrollWidth, name\.clientWidth\)\) \(head\.querySelector\(":scope > span:not\(\.pj-cap\)"\) as HTMLElement \| null\)\?\.remove\(\);\s*\}/, "the name and the kind are looked up only when the capsule is in the row");
  assert.match(ov, /el\.classList\.toggle\("pj-open", frame\.panelShown\);/);
});

test("without the capsule both rows are as shipped, and nothing shipped is redefined", () => {
  const css = code("projects/projects.css");
  assert.match(css, /\.int-head\.pj-fit b \{/);
  assert.match(css, /\.view\.overview\.pj-open \{/);
  assert.doesNotMatch(css, /^\.(overview|pill|card|pills|who|int-head)( [^{]*)? \{/m, "no shipped rule is redefined, only pj- classes and pj- modifiers");
  assert.doesNotMatch(code("style.css"), /pj-/, "the shipped stylesheet gains nothing here (Task 7 adds one wing selector)");
});

test("buildPill is exported as buildAgentPill, and the chevron icon is in ICONS", () => {
  assert.match(v, /export function buildAgentPill\(task: AgentTask, cat: string, actions: ViewActions\): HTMLElement \{/);
  assert.doesNotMatch(v, /\bbuildPill\(/, "its one caller is renamed too");
  assert.match(code("views/icons.ts"), /chevronDown: "M5\.5 9 12 15\.5 18\.5 9",/);
});

const pj = code("views/projects.ts"), isl = code("island/island.ts");

test("the chevron is wired: the island's toggleExpanded flips the model's flag and notifies", () => {
  assert.match(isl, /toggleExpanded: \(\) => \{\s*State\.projects\.toggleExpanded\(\);\s*State\.notify\(\);\s*\}/);
});

test("the idle card's key holds frame.chevron, so the card rebuilds (and gives the kind word back) when the capsule goes", () => {
  const key = ov.slice(ov.indexOf("const key = ["), ov.indexOf('].join("~");'));
  assert.match(key, /frame\.chevron/);
});

test("the peek is synced at the top of sync, outside the Claude-only branch, and the section's hidden branch lets go of it", () => {
  const top = ov.slice(ov.indexOf("sync() {"), ov.indexOf("if (frame.usesProjects) {"));
  assert.match(top, /peek\.sync\(\);/);
  const branch = ov.slice(ov.indexOf("if (frame.usesProjects) {"), ov.indexOf("if (projectsShown) {"));
  assert.doesNotMatch(branch, /peek\.sync\(\)/, "not only inside the Claude-only branch");
  const start = pj.indexOf("export function buildClaudePanel");
  const hidden = pj.slice(start, pj.indexOf("const open = src.open();", start));
  assert.match(hidden, /peek\.leave\(\);/, "a hidden section takes its tile's peek with it");
});

test("pruneMiniBots runs right after the Claude-only grid takes the shipped pills' place: their cats leave the frame loop", () => {
  assert.match(ov, /pills\.replaceWith\(grid\.el\);\s*pruneMiniBots\(\);/);
});

test("the section takes the frame the overview already holds, so the shipped path computes it once", () => {
  assert.match(ov, /panel\.sync\(frame\);/);
  assert.match(pj, /sync\(f: ProjectsFrame = src\.frame\(\)\): void \{|sync\(f: ProjectsFrame = src\.frame\(\)\) \{/);
});
