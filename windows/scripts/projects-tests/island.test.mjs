import test from "node:test";
import assert from "node:assert/strict";
import { code, source } from "./util.mjs";
import { badgeTitle } from "../../src/projects/present.ts";
import { badgeTitle as shelfBadgeTitle } from "../../src/shelf/badge.ts";

// The island frame (Task 7 of P-tauri): the big cat's look, the kittens, the section's height, the compact count, the tick and the tray item. The pins are the
// shape of the wiring in island.ts, main.ts, style.css and the tray; the behaviour of each rule has its own test file.

const i = code("island/island.ts"), main = code("main.ts");

test("the big cat's look: the big card's project's coat and state in the open Claude-only card, else today's; one source for coat, collar, dance and state", () => {
  assert.match(i, /private bigLook\(\): \{ coat: string; state: BotStateName \} \{[\s\S]*?State\.mode === "expanded" && State\.view === "overview" && f\.usesProjects && f\.big/);
  assert.match(i, /const focus = State\.focusTask;\s*const look = this\.bigLook\(\);\s*this\.engine\.setCoat\(look\.coat\);\s*this\.engine\.collarColor = bigCatCollar\(look\.state, focus\?\.color\);/);
  assert.match(i, /this\.engine\.setDancing\(shouldDance\(State\.musicPlaying, look\.state, State\.mode\)\);/);
  assert.match(i, /syncMiniBotStates\(State\.tasks\);\s*this\.engine\.setState\(this\.bigLook\(\)\.state\);/);
});

test("the kittens: the big card's project's subagents in the Claude-only card; the shipped line stays; both step aside while a peek shows", () => {
  assert.match(i, /const big = shown && cast\.big\.pill && !State\.desktopNotchEmpty \? State\.kittenView\(cast\.big\.pill, now\) : \[\]/);
  assert.match(i, /projectKittens\(/);
  assert.match(i, /this\.drawKittenLayer\(dt, greetingActive \|\| this\.peeking\(\)\);/);
  assert.match(i, /this\.botCanvas\.style\.opacity = visible && !State\.desktopNotchEmpty \? "1" : "0";\s*if \(this\.peeking\(\)\) this\.botCanvas\.style\.opacity = "0";/);
});

test("the section's height follows the frame, on the existing spring", () => {
  assert.match(i, /State\.projectsNow\(\)\.panelShown \? PANEL_EXTRA : 0/);
  assert.match(i, /if \(panelShown !== this\.panelWasShown\) \{\s*this\.panelWasShown = panelShown;\s*this\.animateGeometry\(!panelShown\);/);
});

test("the compact count: the shelf badge's rules and spot, waiting first; a click opens the Projects screen; nothing reveals", () => {
  assert.match(i, /const showWait = badgeShown\(State\.mode, frame\.view\.waiting, greetingActive\);/);
  assert.match(i, /const showBadge = badgeShown\(State\.mode, State\.shelf\.count, greetingActive\) && !showWait;/);
  assert.match(i, /this\.waitBadge\.addEventListener\("click", \(e\) => \{ e\.stopPropagation\(\); this\.openProjects\(\); \}\);/);
  assert.match(i, /this\.waitBadge\.title = badgeTitle\(frame\.view\.waiting\);/);
  assert.match(code("style.css"), /#island\.wing-on #projects-badge,\s*#island\.wing-on #shelf-badge \{/);
});

test("the tick runs only while expanded with a live project; the peeks are let go on fold", () => {
  assert.match(i, /this\.projectsTick\.sync\(State\.mode === "expanded" && frame\.view\.projects\.length > 0\);/);
  assert.match(i, /new ProjectsTick\(\{ set: \(fn, ms\) => window\.setTimeout\(fn, ms\), clear: \(id\) => window\.clearTimeout\(id\) \}, \(\) => Date\.now\(\), \(\) => State\.projects\.nextDelay\(\), \(\) => State\.notify\(\)\)/);
  assert.match(i, /if \(mode !== "expanded"\) leaveAllPeeks\(\);/);
});

test("the tray: a Projects item, its words set only when the count changes, and the tray event opens the screen", () => {
  assert.match(main, /case "projects":\s*setPaused\(false\);\s*island\.openProjects\(\);\s*break;/);
  assert.match(main, /if \(n !== lastProjects\) \{\s*lastProjects = n;\s*void Bridge\.projectsMenuText\(n\);/);
  assert.match(source("../src-tauri/src/tray.rs"), /MenuItem::with_id\(app, "projects", "Projects", true, None::<&str>\)\?/);
  assert.match(source("../src-tauri/src/lib.rs"), /tray::projects_menu_text,/);
});

test("the waiting badge says \"Projects, N waiting\" (projects/present.ts); the shelf's badge keeps the shelf's own words under another name", () => {
  assert.match(i, /import \{[^}]*\bbadgeTitle\b[^}]*\} from "\.\.\/projects\/present\.ts";/, "the Projects badge's words come from present.ts");
  assert.match(i, /import \{[^}]*\bbadgeTitle as shelfBadgeTitle\b[^}]*\} from "\.\.\/shelf\/badge";/, "the shelf's function is imported under its own name");
  assert.match(i, /this\.shelfBadge\.title = shelfBadgeTitle\(State\.shelf\.count\);/);
  assert.match(i, /this\.waitBadge\.title = badgeTitle\(frame\.view\.waiting\);/);
  assert.equal(badgeTitle(2), "Projects, 2 waiting");
  assert.equal(shelfBadgeTitle(2), "Shelf: 2 files");
});

test("the Projects frame is computed once per animation frame: the frame loop and syncDom compute it; the big cat, its peek and its kittens read the cache", () => {
  const top = i.slice(i.indexOf("private frame = "), i.indexOf("this.updateBotTargets();"));
  assert.match(top, /if \(State\.mode === "expanded"\) this\.projectsFrame = State\.projectsNow\(\);/, "only the expanded island computes it per frame");
  for (const name of ["private bigLook", "private peeking", "private drawKittenLayer"]) {
    const start = i.indexOf(name);
    assert.ok(start >= 0, `${name} exists`);
    const body = i.slice(start, i.indexOf("\n  }\n", start));
    assert.doesNotMatch(body, /State\.projectsNow\(\)/, `${name} reads this frame's projects frame, not a new one`);
  }
  assert.match(i, /private peeking\(\): boolean \{\s*return State\.mode === "expanded" && State\.view === "overview" && this\.projectsThisFrame\(\)\.peeking !== null;/, "a folded island, or another view, is never peeking, so it reads no frame");
});

test("the big cat's glow follows bigLook and steps aside under a peek; the dizzy recovery returns to bigLook's state", () => {
  assert.match(i, /const glow = this\.bigLook\(\)\.state;\s*const color = botGlowColor\(glow\);/);
  assert.match(i, /this\.botGlow\.style\.display = this\.peeking\(\) \? "none" : "block";/, "a peek hides the glow");
  assert.match(i, /this\.botGlow\.style\.opacity = String\(botGlowOpacity\(glow\)\);/);
  assert.equal((i.match(/this\.engine\.setState\(this\.bigLook\(\)\.state\);/g) || []).length, 2, "syncDom and the dizzy recovery");
  assert.doesNotMatch(i, /setState\(State\.effectiveState\)/, "no state is read off the cast's effective state alone");
});

test("a peek is let go when the island's view leaves the overview: setView and expand call leaveAllPeeks first, and peeking needs the overview", () => {
  const body = (header) => {
    const at = i.indexOf(header);
    assert.ok(at >= 0, `no ${header}`);
    return i.slice(at, i.indexOf("\n  }\n", at));
  };
  for (const header of ["  expand(view: IslandViewName) {", "  setView(view: IslandViewName) {"]) {
    assert.match(body(header), /if \(view !== "overview"\) leaveAllPeeks\(\);/, `${header.trim()} lets go of the peeks`);
  }
  assert.match(i, /private peeking\(\): boolean \{\s*return State\.mode === "expanded" && State\.view === "overview" && this\.projectsThisFrame\(\)\.peeking !== null;/);
});

test("the Pin menu's failures: a build or use that throws logs one fixed sentence and drops the menu so the next right-click rebuilds it; a pending release is cleared", () => {
  const body = (() => {
    const at = i.indexOf("  private async showProjectMenu(id: string): Promise<void> {");
    assert.ok(at >= 0, "showProjectMenu");
    return i.slice(at, i.indexOf("\n  }\n", at));
  })();
  assert.match(i, /private projectMenuRelease: number \| null = null;/, "the release's timer id is kept");
  assert.match(body, /window\.clearTimeout\(this\.projectMenuRelease\)/, "an earlier release is cleared at the start");
  assert.match(body, /catch \{\s*console\.error\("\[notchmeow\] pin menu failed"\);\s*this\.projectMenu = null;/, "a use that throws: the fixed sentence, the menu dropped");
  assert.match(body, /catch \{ this\.projectMenu = null; console\.error\("\[notchmeow\] pin menu failed"\);/, "a build that throws: the same fixed sentence");
  assert.match(body, /finally \{[\s\S]*this\.projectMenuRelease = window\.setTimeout\(\(\) => \{[^}]*menuHold\(false, this\.wasInIsland\)[^}]*\}, PIN_MENU_RELEASE_MS\);/, "the finally still schedules the single release");
  assert.equal((i.match(/\[notchmeow\] pin menu failed/g) || []).length, 2, "only the two fixed sentences; never the error");
});
