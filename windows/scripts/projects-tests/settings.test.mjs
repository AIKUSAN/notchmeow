import test from "node:test";
import assert from "node:assert/strict";
import { code } from "./util.mjs";

// Settings → Cat → Agents' cats → Project cats (Task 9 of P-tauri): the island tells the Settings window the live folder names, and the card is built in the Cat section.

test("the island answers the settings window with the live names whenever they change and when asked; never a path", () => {
  const main = code("main.ts");
  assert.match(main, /const live = State\.projects\.liveProjects\(State\.projectsNow\(\)\.view\);/);
  assert.match(main, /await onEvent<null>\("projects-live-ask", \(\) => void Bridge\.emitProjectsLive\(State\.projects\.liveProjects\(State\.projectsNow\(\)\.view\)\)\);/);
});

test("the settings window listens before its first await, asks once booted, and passes the names to the Cat page", () => {
  const app = code("settings/app.ts");
  assert.ok(app.indexOf('backend.on<LiveProject[]>("projects-live", ') < app.indexOf("await backend.boot()"));
  assert.match(app, /backend\.askProjectsLive\(\);/);
  assert.match(app, /projects: \(\) => projectsLive,/);
  assert.match(code("settings/backend.ts"), /askProjectsLive: \(\) => void Bridge\.askProjectsLive\(\),/);
});

test("the card: in Agents' cats after the agents' card, in every display mode, built from the kit, with the Mac's words", () => {
  const cat = code("settings/cat.ts"), r = code("settings/projectcats.ts");
  assert.match(cat, /if \(projects\) groups\.agentcats\.push\(projects\.el\);/);
  // Concern 2 ruling: the card is built only with the agents' group, so the loop starts through `display` (which that tab always builds) and `drawing` needs no clause of its own.
  assert.match(cat, /const projects = want\("agentcats"\) \? projectCatsCard\(/);
  assert.match(cat, /const display = want\("agentcats"\) \? displayRows\(/);
  assert.doesNotMatch(cat, /drawing = [^;]*projects/, "drawing does not name projects");
  assert.doesNotMatch(cat, /projects\.el\.hidden|projectsCard\.hidden/, "not hidden by the mode");
  assert.match(cat, /display\?\.draw\(dt\);\s*projects\?\.draw\(dt\);/);
  assert.match(r, /card\("Project cats", null,/);
  for (const w of ["projectCatRows(", "withProjectCat(", "withoutProjectCat(", "EMPTY_SETTINGS", "CATS_HELP", "setValue("]) assert.ok(r.includes(w), w);
  assert.doesNotMatch(r, /\.value = /, "a picker is written through setValue only");
  // A refused pick leaves the focused picker on the refused cat: the revert is forced for that one control, with the cat the block holds now.
  assert.match(r, /forceValues\(\(\) => setValue\(pick, catNow\(r\.catKey, r\.cat\)\), pick\);/, "a refused pick reverts the focused picker");
  // The 256 help line comes below the rows (CatSettingsView.swift).
  assert.match(r, /card\("Project cats", null, slot, help\(CATS_HELP\)\);/, "the help line is below the rows");
});
