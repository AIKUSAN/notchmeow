import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { INTEGRATION_AGENTS } from "../../src/core/state.ts";

const read = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("the Claude Code pill is labelled Claude Code, and its ID is the frozen one", () => {
  const pill = INTEGRATION_AGENTS.find((t) => t.id === "integration_claude");
  assert.ok(pill, "integration_claude still exists");
  assert.equal(pill.name, "Claude Code");
  assert.equal(pill.color, "#F5F6F8", "its colour did not change");
});

test("no source of the pill, its card or its reset still says VS Code as the pill's label", () => {
  assert.match(read("island/hooks.ts"), /t\.name = "Claude Code";/);
  assert.match(read("views/views.ts"), /const label = task\.id === "integration_claude" \? "Claude Code" : task\.name;/);
  assert.match(read("views/integrations.ts"), /task\.id === "integration_claude" \? "Claude Code" : task\.name/);
  for (const f of ["island/hooks.ts", "views/views.ts", "views/integrations.ts", "core/state.ts"]) {
    assert.doesNotMatch(read(f), /"VS Code"/, `${f} has no "VS Code" label`);
  }
});
