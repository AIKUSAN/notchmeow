import test from "node:test";
import assert from "node:assert/strict";
import { projectEventFrom } from "../../src/projects/core.ts";
import { PROJECT_SCENARIOS } from "../../src/projects/scenarios.ts";

// The dev scenarios (P-tauri, Task 4): eight scripted runs of Claude Code sessions in made-up folders under C:/dev/, every payload a hook event the registry reads.

const NAMES = ["two", "appWait", "cardWait", "collide", "subagents", "many", "other", "end"];

test("the eight scenarios, in the order the dev panel lists them", () => {
  assert.deepEqual(Object.keys(PROJECT_SCENARIOS), NAMES);
});

test("every payload gives an event through projectEventFrom; the other agent's are kind other", () => {
  for (const [name, s] of Object.entries(PROJECT_SCENARIOS)) {
    assert.ok(s.steps.length > 0, `${name} has steps`);
    for (const step of s.steps) {
      const ev = projectEventFrom(step.payload, 0);
      assert.ok(ev !== null, `${name} at ${step.at}`);
      if (name === "other") assert.equal(ev.kind, "other", `${name} at ${step.at}`);
    }
  }
});

test("every cwd starts with C:/dev/, and `at` never decreases inside a scenario", () => {
  for (const [name, s] of Object.entries(PROJECT_SCENARIOS)) {
    let last = -Infinity;
    for (const step of s.steps) {
      assert.ok(step.at >= last, `${name}: at ${step.at} after ${last}`);
      last = step.at;
      if (typeof step.payload.cwd === "string") assert.ok(step.payload.cwd.startsWith("C:/dev/"), `${name}: ${step.payload.cwd}`);
    }
  }
});

test("many has seven distinct project folders", () => {
  const cwds = new Set(PROJECT_SCENARIOS.many.steps.map((s) => s.payload.cwd));
  assert.equal(cwds.size, 7);
  assert.equal(new Set([...cwds].map((c) => String(c).split("/").pop())).size, 7);
});
