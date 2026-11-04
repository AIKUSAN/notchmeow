// Pins for the parked minors B of the first Settings plan (Task 6, part 2): the focus after a keyboard choice, the window shown again (fit, away, the servers' listener),
// the Devices name on hide, the held slider, the saves' guards and the dead CSS. They read the source as text, because Node has no DOM; the rules themselves are replayed in
// route, held, drafts, aicache (outcome tests) and the picture script shows the rest.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { sliceBetween } from "./slice.mjs";

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const shell = read("src/settings/shell.ts");
const app = read("src/settings/app.ts");
const devices = read("src/settings/devices.ts");
const ai = read("src/settings/ai.ts");
const services = read("src/settings/services.ts");
const css = read("src/settings/settings.css");
const kitTest = read("scripts/settings-tests/kit.test.mjs");
const contrast = read("scripts/settings-tests/contrast.test.mjs");
const kit = read("src/settings/kit.ts");

/** The app's start function, with its line comments taken out (a comment cannot satisfy an order). */
const startBody = () => sliceBetween(app, "export async function startSettingsApp(", "\n}\n").replace(/\/\/[^\n]*/g, "");

// B5: keyboard focus lands on the new tab or sidebar button; the tab bar fits again when the window is shown.
test("shell.ts: select takes the focus from the old sidebar or tab button with focusAfter, and the new one takes it", () => {
  const select = sliceBetween(shell, "  function select(place: Place): void {", "\n  }\n");
  assert.ok(select.includes("focusAfter("), "select decides with the pure rule");
  assert.match(select, /navs\.get\(current\.page\)\?\.focus\(\)/, "a sidebar choice takes the focus to its sidebar button");
  assert.match(select, /\[role="tab"\]\[aria-selected="true"\]/, "a tab choice takes the focus to the selected tab");
  assert.ok(select.indexOf("focusAfter(") > select.indexOf("paint();"), "the new buttons exist (paint) before the focus moves");
  assert.ok(select.indexOf("const was = ") >= 0 && select.indexOf("const was = ") < select.indexOf("view?.dispose?.()"), "the focus is read before the old page is disposed");
  assert.match(shell, /return \{ el, select, sync: \(\) => view\?\.sync\?\.\(\), current: \(\) => current, banner, pin, fit: \(\) => bar\?\.fit\(\) \};/, "the shell exposes fit()");
});

test("app.ts: the window's focus and visibility handlers fit the tab bar through the shell", () => {
  const focus = sliceBetween(app, 'window.addEventListener("focus", () => {', "});\n");
  assert.ok(focus.includes("shell?.fit()"), "focus fits the tab bar");
  const vis = sliceBetween(app, 'document.addEventListener("visibilitychange", () => {', "});\n");
  assert.ok(vis.includes("shell?.fit()"), "a window shown again fits the tab bar");
});

// B7: a tray show with no focus event still refreshes; the servers' listener is registered before the first await.
test("app.ts: away is cleared by the first pointerdown or keydown after a hide, through one-shot listeners re-armed at each hide", () => {
  const hidden = sliceBetween(app, 'backend.on<unknown>("settings-hidden", () => {', "\n  });\n");
  assert.match(hidden, /armAway\(\);/, "each hide re-arms the listeners");
  const arm = sliceBetween(app, "  function armAway(): void {", "\n  }\n");
  assert.match(arm, /addEventListener\(t, onFirstAct, \{ once: true \}\)/, "one-shot listeners");
  assert.match(arm, /\["pointerdown", "keydown"\]/, "pointerdown and keydown");
  const act = sliceBetween(app, "  const onFirstAct = () => {", "\n  };\n");
  assert.match(act, /if \(!away\) return;/, "it acts only while away");
  assert.match(act, /away = false;\s*void aiArrive\(\);/, "it clears away and runs the arrival");
});

test("app.ts: ai-servers-changed is registered before the first await, and the cache exists before it", () => {
  const body = startBody();
  const listen = body.indexOf('backend.on<AiServer[]>("ai-servers-changed"');
  const firstAwait = body.indexOf("await ");
  assert.ok(listen > 0, "the listener is in startSettingsApp");
  assert.ok(firstAwait < 0 || listen < firstAwait, "the listener is registered before any await");
  const cache = body.indexOf("const ai = new AiCache(");
  assert.ok(cache > 0 && cache < listen, "the cache is built before the listener that uses it");
  assert.match(body, /new AiCache\(backend, CLOUD_PROVIDERS, \(key\) => drafts\?\.isSaved\(key\) \?\? false\)/, "its presence reads the book once it exists");
});

test("app.ts: a settings-place that names the page already shown does not rebuild it (no typing or banner lost)", () => {
  const handler = sliceBetween(app, 'backend.on<string>("settings-place", (p) => {', "\n  });\n");
  assert.match(handler, /if \(shell && !alreadyShown\(pending, shell\.current\(\)\)\) shell\.select\(pending\);/, "select runs only when the place changes");
});

// B6: the Devices section's Name is put back to the stored name when the window hides.
test("devices.ts: reset() puts the stored name back into the field and clears the refusal", () => {
  const body = sliceBetween(devices, "  function reset(): void {", "\n  }\n");
  assert.match(body, /name\.value = snap\.name;/);
  assert.match(body, /nameRefused = false;/);
  assert.match(body, /paintName\(\);/);
  assert.match(devices, /return \{\s*el,\s*sync,\s*reset,/, "reset is on the section");
  assert.match(devices, /export function devicesSection\(host: DevicesHost\): \{ el: HTMLElement; sync\(s: LinkSnapshot\): void; reset\(\): void; dispose\(\): void \}/);
});

test("app.ts: a hide puts the Devices name back through the section's reset", () => {
  const hidden = sliceBetween(app, 'backend.on<unknown>("settings-hidden", () => {', "\n  });\n");
  assert.match(hidden, /devicesView\?\.reset\(\)/, "the open Devices section is reset");
  assert.match(app, /case "devices": \{[\s\S]*?onDevices\(d\);/, "buildPage hands the section to the app");
});

// B10: the dead CSS is gone; the word-break pin keeps the rule that is still used.
test("settings.css: no .spacer and no .path rule (no file in windows/src uses either class)", () => {
  assert.doesNotMatch(css, /^\.spacer \{/m);
  assert.doesNotMatch(css, /^\.path \{/m);
  assert.doesNotMatch(css, /^code,\s*$\n\.path/m);
  assert.match(css, /^code \{[^}]*word-break: break-all/m, "code keeps its word-break");
});

test("the word-break pin of kit.test follows the code rule, not the removed .path rule", () => {
  assert.match(kitTest, /code \\\{\[\^\}\]\*word-break: break-all/, "the pin names the code rule");
  assert.doesNotMatch(kitTest, /\.path \\\{/, "no pin keeps .path alive");
});

// B11 wiring: the Cat page's closure uses reconcile.
test("app.ts: the Cat page works from reconcile(held, latest); each slider event goes through hold and a release saves what released() gives over the latest settings", () => {
  const cat = sliceBetween(app, '    case "cat": {', "\n    }\n");
  assert.match(cat, /let held: Held \| null = null;/);
  assert.match(cat, /cat: \(\) => reconcile\(held, ctx\.settings\(\)\.cat\),/);
  assert.match(cat, /const latest = ctx\.settings\(\)\.cat;/);
  assert.match(cat, /if \(!final\) \{ held = hold\(held, latest, next\); return; \}/);
  assert.match(cat, /const block = released\(held, latest, next\);\s*held = null;\s*void ctx\.save\(\{ \.\.\.ctx\.settings\(\), cat: block \}\);/);
  assert.match(app, /import \{ hold, reconcile, released, type Held \} from "\.\/held\.ts";/);
});

// B16: the contrast slicer finds each rule by its own selector; the shared slicer replaces the three near-identical ones.
test("contrast.test.mjs: rules are found by a rule-anchored slice (ruleBody), not the first indexOf match", () => {
  assert.match(contrast, /import \{ ruleBody \} from "\.\/slice\.mjs";/);
  assert.doesNotMatch(contrast, /bodyAt\(/, "no rule is cut by a first-match indexOf");
  assert.doesNotMatch(contrast, /^function bodyAt\(/m, "the local slicer is gone");
});

test("kit.test.mjs and drift.test.mjs use the shared slicer, not their own", () => {
  assert.match(kitTest, /from "\.\/slice\.mjs"/);
  assert.doesNotMatch(kitTest, /^function (fnText|bodyOf)\(/m);
  const drift = read("scripts/settings-tests/drift.test.mjs");
  assert.match(drift, /from "\.\/slice\.mjs"/);
  assert.doesNotMatch(drift, /^function swiftBody\(/m);
});

// B17: removeKey returns early while a save for the same card is in flight; the writing sets live at module level.
test("ai.ts: removeKey returns early while a save for its provider is in flight, and the writing set is module-level", () => {
  assert.match(ai, /^const writing = new Set<KeyProvider>\(\);/m, "module level, so it survives a tab switch");
  const remove = sliceBetween(ai, "  async function removeKey(p: KeyProvider): Promise<void> {", "\n  }\n");
  assert.match(remove, /if \(!c \|\| !canStartWrite\(writing\.has\(p\)\) \|\| !ctx\.drafts\.canWrite\(c\.key\)\) return;/);
  assert.doesNotMatch(ai, /^  const writing = new Set/m);
});

test("services.ts: removeKey returns early while the card's save is in flight, and the writing set is module-level", () => {
  assert.match(services, /^const writing = new Set<string>\(\);/m);
  assert.doesNotMatch(services, /^  const writing = new Set/m);
  const remove = sliceBetween(services, "    async function removeKey(f: ServiceField): Promise<void> {", "\n    }\n");
  assert.match(remove, /if \(!canStartWrite\(writing\.has\(def\.id\)\) \|\| !ctx\.drafts\.canWrite\(f\.key\)\) return;/);
});

// B18: a save marks what was sent; text typed during the write stays.
test("ai.ts and services.ts: a successful save marks the text it sent (markSaved with the sent text)", () => {
  assert.match(ai, /const typed = ctx\.drafts\.text\(c\.key\);\s*const text = typed\.trim\(\);/);
  assert.match(ai, /ctx\.drafts\.markSaved\(c\.key, true, typed\);/);
  assert.match(services, /const typed = ctx\.drafts\.text\(id\);[\s\S]*?secretSet\(id, typed\.trim\(\)\);/);
  assert.match(services, /ctx\.drafts\.markSaved\(id, true, typed\);/);
});

// B20: a failed server look-up is caught and noted in the card.
test("ai.ts refreshServers: a rejected discovery is caught into undefined, the list is kept, and the card shows discoveryMsg's text", () => {
  const body = sliceBetween(ai, "  async function refreshServers(): Promise<void> {", "\n  }\n");
  assert.match(body, /const found = await ctx\.backend\.aiDiscover\(\)\.catch\(\(\) => undefined\);/);
  assert.match(body, /if \(found !== undefined\) ctx\.ai\.setServers\(found\);/);
  assert.match(body, /const text = discoveryMsg\(found, msg\?\.text \?\? null\);\s*if \(text !== msg\?\.text\) msg = text \? \{ kind: "err", text \} : null;/, "an earlier message is kept unless the note changes it");
  assert.match(ai, /import \{ discoveryMsg \} from "\.\/aicache\.ts";/);
});

test("shell.ts: select picks the tab's focus target with focusTarget and the tab bar's own narrow state, never offsetParent", () => {
  const select = sliceBetween(shell, "  function select(place: Place): void {", "\n  }\n");
  assert.match(select, /focusTarget\(bar\.narrow\(\)\)/);
  assert.doesNotMatch(select, /offsetParent/);
  assert.match(kit, /narrow: \(\) => el\.classList\.contains\("narrow"\)/);
});
