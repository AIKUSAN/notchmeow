import test from "node:test";
import assert from "node:assert/strict";
import { code } from "./util.mjs";

// The wiring of the Projects model into the island (Task 4 of P-tauri): the feed, the frame in State, the one model made in main.ts, and the pins that a comment cannot satisfy.

const hooks = code("island/hooks.ts"), main = code("main.ts"), state = code("core/state.ts");

test("the feed is after a chat's own run is routed away, right after the Sidekick's, before any refusal", () => {
  const at = hooks.indexOf("  State.projects.hook(payload, stepBack?.host);");
  assert.ok(at > 0 && hooks.indexOf("State.projects.hook(", at + "  State.projects.hook(payload, stepBack?.host);".length) < 0, "once, and in code");
  assert.ok(hooks.indexOf('routeHook(payload, State.claudeSessions) === "chat"') < at);
  const hub = hooks.indexOf("  Hub.sk?.hook(payload);");
  assert.ok(hub > 0 && hub < at);
  assert.doesNotMatch(hooks.slice(hub, at), /return/, "no refusal between the Sidekick's feed and the Projects feed (comments blanked)");
  assert.ok(at < hooks.indexOf("  switch (name) {"));
});

test("main.ts makes the one model with the home folder and the skewed clock, before the hooks are registered", () => {
  const made = main.indexOf('State.projects = new ProjectsModel({ home: boot?.home ?? "", now: () => Date.now() + Skew.ms });');
  assert.ok(made > 0 && made < main.indexOf("  registerHookHandlers(island);"));
});

test("State's frame takes the cat block, every pill (the four switches included), the focus and Two cats", () => {
  const start = state.indexOf("projectsNow(): ProjectsFrame {");
  const fn = state.slice(start, state.indexOf("\n  }\n", start));
  assert.match(fn, /activePills: \[\.\.\.this\.settings\.activeIntegrations, \.\.\.this\.tasks\.map\(\(t\) => t\.id\)\]/);
  assert.match(fn, /focusId: this\.focusId,/);
  assert.match(fn, /twoCats: this\.cast\.second !== null,/);
});

test("no timer and no loop in the projects modules", () => {
  for (const f of ["projects/model.ts", "projects/present.ts", "projects/cells.ts", "projects/clock.ts", "projects/core.ts", "projects/scenarios.ts"])
    assert.doesNotMatch(code(f), /setInterval|setTimeout|requestAnimationFrame/, f);
});

test("feeding the registry raises no alert: attentionNeeded and the tuck-away rule do not read it", () => {
  assert.doesNotMatch(state.slice(state.indexOf("get attentionNeeded"), state.indexOf("get focusTask")), /projects/);
  assert.doesNotMatch(code("island/tuckaway.ts"), /projects/i);
});
