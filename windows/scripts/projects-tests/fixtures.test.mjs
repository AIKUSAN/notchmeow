import test from "node:test";
import assert from "node:assert/strict";
import * as P from "../../src/projects/core.ts";
import { pickCat } from "../../src/cat/agentcat.ts";
import { rng } from "../../src/cat/base.ts";
import { CAT_IDS } from "../../src/cat/presets.ts";
import { load, rows } from "./util.mjs";

// Every fixture of tests/fixtures/projects/ is generated from shared/projects-core.js. A group whose count changes on purpose (a fixture change) updates the
// number here, as the Mac's PJFixtureRows does. A failing row names itself through c.name.

const T = 1_760_000_000_000;

test("project-cases.json", () => {
  const f = load("project-cases.json");
  for (const c of rows(f, "projectOf", 25)) assert.deepEqual(P.projectOf(c.cwd, c.roots, c.home), c.expect, c.name);
  for (const c of rows(f, "names", 19)) assert.deepEqual(P.projectNames(c.roots, c.home), c.expect, c.name);
  for (const c of rows(f, "roles", 4)) assert.deepEqual(P.rolesOf(c.sessions), c.expect, c.name);
  for (const c of rows(f, "order", 2)) assert.deepEqual(P.sessionOrder(c.rows), c.expect, c.name);
  for (const c of rows(f, "ids", 2)) {
    const reg = P.registryApply(P.emptyRegistry(), P.projectEventFrom({ hook_event_name: "UserPromptSubmit", session_id: "s1", cwd: c.root }, T));
    assert.equal(P.projectsView(reg, T).projects[0].id, c.expect, c.name);
  }
});

test("event-cases.json", () => {
  for (const c of rows(load("event-cases.json"), "cases", 53)) assert.deepEqual(P.projectEventFrom(c.payload, c.now, c.waitIn), c.expect, c.name);
});

test("registry-cases.json: every step is a payload or a view, every view, the notes, the presentation and the caps", () => {
  const f = load("registry-cases.json");
  let payloads = 0, views = 0;
  for (const c of rows(f, "cases", 31)) {
    let reg = P.emptyRegistry(c.home);
    for (const s of c.steps) {
      assert.notEqual("payload" in s, "view" in s, `${c.name}: a step is a payload or a view`);
      if (s.payload) { payloads++; reg = P.registryApply(reg, P.projectEventFrom(s.payload, s.at, s.waitIn)); continue; }
      views++;
      const view = P.projectsView(reg, s.at, {});
      assert.deepEqual(view, s.view, c.name);
      if (s.notes) assert.deepEqual(view.projects.flatMap((p) => p.sessions).filter((r) => r.note !== "").map((r) => `${r.label}:${r.note}`), s.notes, c.name);
    }
  }
  assert.deepEqual([payloads, views], [103, 52]);
  for (const c of rows(f, "presentation", 7)) {
    let reg = P.emptyRegistry(c.home);
    for (const s of c.payloads) reg = P.registryApply(reg, P.projectEventFrom(s.payload, s.at));
    assert.deepEqual(P.projectsView(reg, c.at, c.opts), c.view, c.name);
  }
  for (const c of rows(f, "caps", 8)) {
    let reg = P.emptyRegistry(c.home);
    for (const e of c.events) reg = P.registryApply(reg, P.projectEventFrom(e.payload, e.at));
    const got = { sessions: reg.sessions.map((s) => `${s.id}#${s.seq}`), nextSeq: reg.nextSeq,
      subagents: Object.fromEntries(reg.sessions.filter((s) => s.subagents.length).map((s) => [s.id, s.subagents.map((k) => k.id)])),
      lastAt: Object.fromEntries(reg.sessions.map((s) => [s.id, s.lastAt])) };
    for (const k of Object.keys(c.expect)) assert.ok(k in got, `${c.name}: expect key ${k} is one the test reads`);
    assert.deepEqual(Object.fromEntries(Object.keys(c.expect).map((k) => [k, got[k]])), c.expect, c.name);
  }
});

test("state-cases.json", () => {
  const f = load("state-cases.json");
  for (const c of rows(f, "sessions", 30)) assert.deepEqual(P.sessionStateAt(c.session, c.now), c.expect, c.name);
  for (const c of rows(f, "projects", 6)) assert.equal(P.projectStateOf(c.states), c.expect, c.name);
  for (const c of rows(f, "agoCases", 5)) assert.equal(P.agoOf(c.now, c.lastAt), c.expect, c.name);
});

test("order-cases.json", () => {
  const f = load("order-cases.json");
  for (const c of rows(f, "order", 4)) assert.deepEqual(P.projectOrder(c.projects).map((p) => p.id), c.expect, c.name);
  for (const c of rows(f, "bigCard", 8)) assert.deepEqual(P.bigCardOf(c.projects, c.pinned, c.clicked), c.expect, c.name);
  for (const c of rows(f, "waiting", 3)) assert.equal(P.waitingCount(c.projects), c.expect, c.name);
});

test("claude-only-cases.json", () => {
  const f = load("claude-only-cases.json");
  for (const c of rows(f, "claudeOnly", 7)) assert.equal(P.claudeOnly(c.activePills, c.otherAgentSeen), c.expect, c.name);
  for (const c of rows(f, "layout", 5)) assert.equal(P.islandLayout(c.current, c.claudeOnly, c.open), c.expect, c.name);
});

test("cat-cases.json", () => {
  const f = load("cat-cases.json");
  for (const c of rows(f, "cat", 11)) assert.deepEqual(P.projectCatOf(c.catKey, c.projectCats, c.mainCat), c.expect, c.name);
  for (const c of rows(f, "clean", 9)) assert.deepEqual(P.cleanProjectCats(c.raw), c.expect, c.name);
});

test("step-cases.json", () => {
  const f = load("step-cases.json");
  for (const c of rows(f, "steps", 13)) assert.equal(P.cleanStep(c.text), c.expect, c.name);
  for (const c of rows(f, "views", 1)) {
    let reg = P.emptyRegistry(c.home);
    for (const s of c.payloads) reg = P.registryApply(reg, P.projectEventFrom(s.payload, s.at, s.waitIn));
    assert.deepEqual(P.projectsView(reg, c.at, c.opts), c.view, c.name);
  }
});

test("the app's own cats agree: the core's pick is cat/agentcat.ts pickCat with cat/base.ts rng, and CAT_IDS are presets.ts's", () => {
  assert.deepEqual([...P.CAT_IDS], [...CAT_IDS]);
  for (let i = 0; i < 300; i++) for (const main of CAT_IDS) assert.equal(P.projectCatOf(`n${i}`, {}, main).cat, pickCat([main], rng(parseInt(P.fnv1a(`n${i}`), 16)), null));
});

test("a number that is not a number never ages anything (the port's own non-finite case)", () => {
  const reg = P.registryApply(P.emptyRegistry("C:/Users/dev"), P.projectEventFrom({ hook_event_name: "PermissionRequest", session_id: "s1", cwd: "C:/dev/app", tool_name: "Bash" }, T));
  for (const bad of [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
    assert.equal(P.projectEventFrom({ hook_event_name: "Stop", session_id: "s1" }, bad), null);
    assert.equal(P.projectsView(reg, bad).waiting, 1);
    assert.equal(P.sessionStateAt(reg.sessions[0], bad).state, "approval");
  }
});
