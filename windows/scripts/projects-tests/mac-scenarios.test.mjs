import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { ProjectsModel } from "../../src/projects/model.ts";

// The Mac's scenarios (tests/fixtures/mac/projects-scenarios.json, read-only), replayed through the Windows model: the same events at the same times, and at each
// step the same expectations that scripts/test-projects-scenarios-core.mjs checks against shared/projects-core.js. An unknown step key, an unknown expect key, a
// wrong step count or a wrong number of expectations fails here too.

const fixture = JSON.parse(fs.readFileSync(new URL("../../../tests/fixtures/mac/projects-scenarios.json", import.meta.url), "utf8"));
const BASE = 1760000000000;
const STEP_COUNTS = { "claude-app-wait": 4, "collide-and-home": 7, end: 4, "other-agent": 2, "two-projects": 11 };
const STEP_KEYS = new Set(["say", "at", "wait_ms", "event", "expect", "waitIn"]);
const EXPECT_KEYS = new Set(["projects", "rows", "notes", "waiting", "layout"]);
const TOTAL_EXPECTATIONS = 70;   // 28 projects lists + 25 project row lists + 2 notes + 9 waiting counts + 6 layouts (the core replay's count)
const IN = { projectCats: {}, mainCat: "shrimpy", activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false };

const isTextList = (x) => Array.isArray(x) && x.every((s) => typeof s === "string");

test("the fixture has the five scenarios, with the step counts the core replay pins", () => {
  assert.deepEqual(Object.fromEntries(Object.entries(fixture.scenarios).map(([n, s]) => [n, s.steps.length])), STEP_COUNTS);
});

test("every Mac scenario replays through the Windows model with its expectations", () => {
  const home = typeof fixture.home === "string" ? fixture.home : "/Users/sam";
  let ran = 0;
  const check = (label, got, want) => { ran++; assert.deepEqual(got, want, label); };
  for (const name of Object.keys(fixture.scenarios).sort()) {
    const w = { t: BASE };
    const m = new ProjectsModel({ home, now: () => w.t });
    for (const [i, step] of fixture.scenarios[name].steps.entries()) {
      const label = `${name} step ${i + 1}`;
      const unknown = Object.keys(step).filter((k) => !STEP_KEYS.has(k));
      assert.deepEqual(unknown, [], `${label}: a step key the test does not read`);
      w.t = BASE + step.at;
      if (step.event !== null && typeof step.event === "object") {
        const payload = { ...step.event };
        if (typeof payload.cwd === "string" && (payload.cwd === "~" || payload.cwd.startsWith("~/"))) payload.cwd = home + payload.cwd.slice(1);
        m.hook(payload, typeof step.waitIn === "string" ? step.waitIn : undefined);
      }
      const frame = m.frame(IN);
      const want = step.expect ?? {};
      assert.deepEqual(Object.keys(want).filter((k) => !EXPECT_KEYS.has(k)), [], `${label}: an expect key the test does not read`);
      if ("projects" in want) {
        assert.ok(isTextList(want.projects), `${label}: projects is a list of text`);
        check(`${label}: projects`, frame.view.projects.map((p) => `${p.name}:${p.state}:${p.waiting}`), want.projects);
      }
      if ("rows" in want) {
        for (const pn of Object.keys(want.rows).sort()) {
          const project = frame.view.projects.find((p) => p.name === pn);
          check(`${label}: rows of ${pn}`, project ? project.sessions.map((s) => `${s.label}:${s.state}`) : [], want.rows[pn]);
        }
      }
      if ("notes" in want) {
        check(`${label}: notes`, frame.view.projects.flatMap((p) => p.sessions).filter((s) => s.note !== "").map((s) => `${s.label}:${s.note}`), want.notes);
      }
      if ("waiting" in want) check(`${label}: waiting`, frame.view.waiting, want.waiting);
      if ("layout" in want) check(`${label}: layout`, frame.layout, want.layout);
    }
  }
  assert.equal(ran, TOTAL_EXPECTATIONS);
});
