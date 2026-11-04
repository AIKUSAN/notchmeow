import test from "node:test";
import assert from "node:assert/strict";
import { DISMISS_KINDS } from "../../src/sidekick/core.ts";
import { KIND_LABELS, defaultSidekick, mutedKinds, withDismissed, withLocal, withSidekickOn, withUnmuted } from "../../src/sidekick/settings.ts";
import { DEFAULT_SETTINGS } from "../../src/core/state.ts";
import { tabs } from "../../src/settings/route.ts";
import { source } from "./util.mjs";

test("a fresh install has everything on and nothing dismissed, in the app's settings too", () => {
  assert.deepEqual(defaultSidekick(), { on: true, local: true, dismissals: { recap: 0, "stuck.loop": 0, "stuck.errors": 0, "stuck.waiting": 0, "stuck.silent": 0 } });
  assert.deepEqual(DEFAULT_SETTINGS.sidekick, defaultSidekick());
});

test("the switches change one thing each, and a dismissal changes only its own kind", () => {
  const s = defaultSidekick();
  assert.deepEqual(withSidekickOn(s, false), { ...s, on: false });
  assert.deepEqual(withLocal(s, false), { ...s, local: false });
  assert.deepEqual(withDismissed(s, "recap").dismissals, { ...s.dismissals, recap: 1 });
  assert.deepEqual(withDismissed(withDismissed(s, "stuck.loop"), "stuck.loop").dismissals["stuck.loop"], 2);
  assert.deepEqual(withDismissed(withDismissed(withDismissed(s, "stuck.loop"), "stuck.loop"), "stuck.loop").dismissals["stuck.loop"], 2, "never above 2");
  assert.deepEqual(withDismissed(s, "bogus"), s, "a word that is not one of the five kinds changes nothing");
});

test("two dismissals mute a kind, Unmute sets it back to 0, and the muted rows come in the contract's order", () => {
  let s = defaultSidekick();
  assert.deepEqual(mutedKinds(s), []);
  for (const k of ["stuck.silent", "recap", "stuck.silent", "recap", "stuck.errors"]) s = withDismissed(s, k);
  assert.deepEqual(mutedKinds(s), ["recap", "stuck.silent"], "stuck.errors was dismissed once: not muted");
  s = withUnmuted(s, "recap");
  assert.deepEqual(mutedKinds(s), ["stuck.silent"]);
  assert.equal(s.dismissals.recap, 0);
  assert.equal(s.dismissals["stuck.errors"], 1, "Unmute touches its own kind only");
});

test("every kind has a row label, in the spec's words", () => {
  assert.deepEqual(Object.keys(KIND_LABELS), [...DISMISS_KINDS]);
  assert.deepEqual(Object.values(KIND_LABELS), ["Away recaps", "Repeated steps", "Repeated errors", "Waiting for your OK", "Gone quiet"]);
});

test("the Settings window's app shows the Sidekick tab of the chat page, cleans the object at start and follows the island's changes", () => {
  const app = source("settings/app.ts");
  assert.ok(tabs("chat").includes("sidekick"), "the chat page shows the Sidekick tab");
  assert.match(app, /case "sidekick": return sidekickSection\(\{/);
  assert.match(app, /sidekick: cleanSidekickSettings\(s\.sidekick\)/);
  assert.match(source("settings/sidekick.ts"), /const write = \(next: SidekickSettings\): void => \{\s*host\.put\(next\);\s*paint\(\);/, "the Sidekick page repaints after every put");
  assert.match(app, /put: \(next\) => void ctx\.save\(\{ \.\.\.ctx\.settings\(\), sidekick: next \}\),/);
  assert.match(app, /on<Partial<Settings>>\("settings-changed", \(s\) => \{[\s\S]*?shell\?\.sync\(\);/);
});

test("the section uses the window's own rows and the spec's words, and runs no timer of its own", () => {
  const sk = source("settings/sidekick.ts");
  for (const s of ["Show notes from the sidekick", "Away recaps", "Stuck nudges", "Choose which", "Permission line", "Nothing is muted", "Muted notes", "Unmute", "No local model found", "Found: ", "Where its words come from", "Quiet times", "Today so far"]) assert.ok(sk.includes(s), s);
  for (const cls of [...sk.matchAll(/class: "([^"]+)"/g)].flatMap((m) => m[1].split(" "))) assert.ok(["row", "hint", "switch", "on"].includes(cls) || cls.startsWith("st-"), `a class that is not the window's own: ${cls}`);
  assert.doesNotMatch(sk, /setInterval|setTimeout|requestAnimationFrame/);
});

test("an off switch says so (the kit writes aria-pressed as a string), each switch is built once and set in place, and paint never takes the section apart", () => {
  const sk = source("settings/sidekick.ts");
  assert.match(source("settings/kit.ts"), /setAttribute\("aria-pressed", String\(on\)\)/, "the state is set explicitly, off included");
  assert.match(sk, /const masterSwitch = switchRow\(/, "the master switch is built once");
  assert.match(sk, /masterSwitch\.set\(/, "paint updates the same switch");
  assert.doesNotMatch(sk, /while \(el\.lastChild/, "paint does not take the whole section apart on every press");
});
