import test from "node:test";
import assert from "node:assert/strict";
import * as L from "../../src/core/layout.ts";
import { code } from "./util.mjs";

// The Projects screen, its rows, pills, peek, actions and the header tab (Task 5 of P-tauri): the geometry, the registration, the wording and the pins that a comment cannot satisfy.

/** The body of a method of comment-blanked source: from the text after `header` (which ends with its `{`) to the brace that closes it. */
function methodBody(text, header) {
  const at = text.indexOf(header);
  assert.ok(at >= 0, `no method "${header.trim()}"`);
  const start = at + header.length;
  let depth = 1, i = start;
  for (; i < text.length && depth > 0; i++) {
    if (text[i] === "{") depth++;
    else if (text[i] === "}") depth--;
  }
  assert.equal(depth, 0, "unclosed method");
  return text.slice(start, i - 1);
}

test("the projects view's geometry, and the overview's section height", () => {
  assert.deepEqual(L.VIEW_LAYOUTS.projects, { height: 240, botX: 46, botY: null, botDiameter: 44, agentMode: "none" });
  assert.equal(L.islandSize("expanded", "projects").h, 240);
  assert.equal(L.islandSize("expanded", "overview").h, 160);
  assert.equal(L.islandSize("expanded", "overview", 0, 1, 92).h, 252);
  assert.equal(L.islandSize("expanded", "settings", 0, 1, 92).h, 160, "only the overview grows");
  assert.equal(L.botPosition("expanded", "overview", 252).cy, L.botPosition("expanded", "overview", 160).cy, "the big cat stays where it is");
  const cat = L.botPosition("expanded", "projects", 240);
  assert.ok(cat.cx + cat.diameter / 2 < 90, "the cat's head ends before the list");
});

test("the view is registered and the header gains one tab, after the + tab", () => {
  const v = code("views/views.ts"), header = v.slice(v.indexOf("export function buildHeader"), v.indexOf("function buildOverview"));
  assert.match(v, /map\.set\("projects", buildProjects\(actions\.projects\)\);/);
  assert.match(header, /const tabProjects = h\("button", \{ class: "tab", title: "Projects", onclick: \(\) => go\("projects"\) \}, svg\(ICONS\.folder, 13\)\);/);
  assert.match(header, /h\("div", \{ class: "tabs" \}, tabHome, tabChat, tabDrop, tabProjects\)/);
  assert.match(header, /tabProjects\.classList\.toggle\("on", v === "projects"\);/);
});

test("the views hold no path, call out to nothing, run no loop, show the Mac's words and key every pill by its cell key", () => {
  const p = code("views/projects.ts");
  assert.doesNotMatch(p, /cwd|cwdOf|Bridge|setInterval|requestAnimationFrame/);
  for (const w of ["EMPTY_SCREEN", "dotClass(", "rowDetail(", "hostWord(", "agoWord(", "moreRowsWord(", "pillNameParts(", "new PeekDwell("]) assert.ok(p.includes(w), w);
  assert.match(p, /kept\.get\(cellKey\(/, "an element is found by its cell's key");
  assert.doesNotMatch(p, /\.children\[|childNodes\[/, "never by its slot");
});

test("the peek takes the left card's own box, caps its lines from the card's height, and lets go of a project that left", () => {
  const p = code("views/projects.ts"), css = code("projects/projects.css");
  assert.match(p, /peekLineCapacity\(/);
  assert.match(css, /\.pj-peek \{[^}]*position: absolute;[^}]*inset: 0;[^}]*border-radius: inherit;[^}]*pointer-events: none;/);
});

test("the island's actions: a row owning the notch card shows it, else the app by openRoute; the cwd goes only to openInVSCode", () => {
  const i = code("island/island.ts");
  assert.match(i, /State\.pendingApproval\?\.sessionId === sessionId/);
  assert.match(i, /openRoute\("integration_claude", State\.claudeApp, row\.host === "claude-app"\)/);
  assert.match(i, /Bridge\.openInVSCode\(State\.projects\.cwdOf\(sessionId\)\)/);
  assert.equal((i.match(/cwdOf\(/g) ?? []).length, 1, "the one read of a session's folder");
  assert.match(i, /openProjects\(\) \{\s*this\.alert\("projects"\);/);
  assert.match(i, /this\.projectMenuRelease = window\.setTimeout\(\(\) => \{\s*this\.projectMenuRelease = null;\s*this\.fsm\.menuHold\(false, this\.wasInIsland\);\s*\}, PIN_MENU_RELEASE_MS\)/, "the Pin menu holds the island a little past its close, and the release forgets its own id");
});

test("the peek's sync leaves when the island is not open and when its project is gone (its own guard, read from the body)", () => {
  const body = methodBody(code("views/projects.ts"), "  sync(): void {");
  const guard = /if \(([^\n]*)\) return this\.leave\(\);/.exec(body);
  assert.ok(guard, "one guard that leaves");
  assert.match(guard[1], /!this\.src\.open\(\)/, "the island is not open");
  assert.match(guard[1], /\|\| p === null/, "its project is not in the frame");
});

test("the Pin menu is a helper of its own, built once into a lazy field; the island keeps one Menu.new (the Wardrobe's)", () => {
  const count = (t, re) => (t.match(re) ?? []).length;
  assert.equal(count(code("core/pinmenu.ts"), /Menu\.new\(/g), 1, "the helper's one menu");
  const i = code("island/island.ts");
  assert.equal(count(i, /Menu\.new\(/g), 1, "the Wardrobe's one");
  assert.equal(count(i, /buildPinMenu\(/g), 1, "called once");
  assert.match(i, /private projectMenu: Promise<PinMenu> \| null = null;/);
  const show = methodBody(i, "  private async showProjectMenu(id: string): Promise<void> {");
  assert.match(show, /this\.projectMenu \?\?= buildPinMenu\(/, "lazily, into the field, inside showProjectMenu");
  assert.match(show, /this\.fsm\.menuHold\(true, this\.wasInIsland\);\s*try \{\s*await parts\.item\.setText/, "held before the setText, which is inside the try");
});

test("ProjectPeek.dispose leaves, takes its element out and is forgotten by the set leaveAllPeeks walks", () => {
  const p = code("views/projects.ts");
  const d = methodBody(p, "  dispose(): void {");
  assert.match(d, /this\.leave\(\);/);
  assert.match(d, /this\.el\.remove\(\);/);
  assert.match(d, /peeks\.delete\(this\);/);
  assert.match(p, /for \(const p of peeks\) p\.leave\(\);/);
});

test("the screen's padding (bottom and leading) equals the cells' SCREEN_BOTTOM and SCREEN_LEADING, so they cannot drift", () => {
  const pad = /\.pj-screen \{[^}]*padding: 4px 12px (\d+)px (\d+)px;/.exec(code("projects/projects.css"));
  assert.ok(pad, "the screen's padding");
  const cells = code("projects/cells.ts");
  assert.equal(Number(/export const SCREEN_BOTTOM = (\d+);/.exec(cells)[1]), Number(pad[1]), "bottom");
  assert.equal(Number(/export const SCREEN_LEADING = (\d+);/.exec(cells)[1]), Number(pad[2]), "leading");
});

test("the peek covers the big card's text: its own background, and a z-index above the shipped .left-body (z 1) that holds that text", () => {
  const css = code("projects/projects.css"), style = code("style.css");
  const peek = /\.pj-peek \{([^}]*)\}/.exec(css);
  assert.ok(peek, "the peek's rule");
  assert.match(peek[1], /background: var\(--card\);/, "the card's own colour");
  const z = Number(/z-index: (\d+);/.exec(peek[1])[1]);
  const leftBody = Number(/\.left-body \{[^}]*z-index: (\d+);/.exec(style)[1]);
  assert.ok(z > leftBody, `the peek (${z}) paints above .left-body (${leftBody})`);
});

test("the same-name pill stacks its folder over its detail, and the section's count keeps the space before its separator", () => {
  const css = code("projects/projects.css");
  assert.match(css, /\.pj-pill \.pj-name \{[^}]*display: flex;[^}]*flex-direction: column;/, "folder over detail");
  assert.match(css, /\.pj-panel-wait \{[^}]*white-space: pre;/, "a flex item drops its leading space otherwise");
});

test("the chevron is a stroked path at 10 px, not the filled open line that reads as a dash", () => {
  assert.match(code("views/projects.ts"), /svg\(ICONS\.chevronDown, 10, \{ stroke: 2 \}\)/);
});

test("ProjectPeek.hide() tells the model the peek is let go (peek(null)); keyedCells keeps its guard and forgets a removed key", () => {
  const p = code("views/projects.ts");
  assert.match(methodBody(p, "  private hide(): void {"), /this\.src\.peek\(null\);/);
  const at = p.indexOf("export function keyedCells(");
  assert.ok(at >= 0, "keyedCells");
  const kc = p.slice(at, p.indexOf("\n}\n", at));
  assert.match(kc, /if \(want !== el\) host\.insertBefore\(el, want\);/, "an element is moved only where it is out of place");
  assert.match(kc, /el\.remove\(\);\s*kept\.delete\(key\);/, "a removed key's element goes and its key is forgotten");
});

test("a removed cell's mini cat is pruned: keyedCells counts what it removed, and both the grid and the panel prune when that is above 0", () => {
  const p = code("views/projects.ts");
  const at = p.indexOf("export function keyedCells(");
  const kc = p.slice(at, p.indexOf("\n}\n", at));
  assert.match(kc, /\): number \{/, "keyedCells returns the count");
  assert.match(kc, /return removed;/);
  const gAt = p.indexOf("export function buildProjectGrid(");
  assert.ok(gAt >= 0, "buildProjectGrid");
  const grid = p.slice(gAt, p.indexOf("\n}\n", gAt));
  assert.match(grid, /gone \+= keyedCells\(/, "the grid's sync sums what keyedCells removed");
  assert.match(grid, /if \(gone > 0\) pruneMiniBots\(\);/, "pruned only when something was removed");
  const panel = methodBody(p, "    sync(f: ProjectsFrame = src.frame()) {");
  assert.match(panel, /const gone = keyedCells\(/, "the panel's sync takes the count");
  assert.match(panel, /if \(gone > 0\) pruneMiniBots\(\);/, "the panel prunes only when something was removed");
});
