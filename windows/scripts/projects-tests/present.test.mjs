import test from "node:test";
import assert from "node:assert/strict";
import * as P from "../../src/projects/core.ts";
import { kittenOrder } from "../../src/cat/kittens.ts";
import {
  STATE_WORDS, EMPTY_SCREEN, EMPTY_SETTINGS, CATS_HELP, CLAUDE_COLOR,
  hostWord, agoWord, sessionsWord, projectsWord, waitingWord, moreWord, moreRowsWord, subagentWord, rowDetail,
  bigStepLine, badgeTitle, pinTitle, dotClass, projectStep, projectKittens, projectTask, projectCatRows,
} from "../../src/projects/present.ts";

// The words of the Projects view (ProjectsLayout.swift's, exact) and the pure helpers the island draws with.

test("the words of the age, the host and the counts", () => {
  assert.deepEqual([0, 1, 59, 60, 125].map(agoWord), ["now", "1 min ago", "59 min ago", "1 h ago", "2 h ago"]);
  assert.deepEqual([hostWord("claude-app"), hostWord("vscode"), hostWord("terminal"), hostWord("x")], ["Claude App", "VS Code", "Terminal", "Terminal"]);
  assert.deepEqual([sessionsWord(1), sessionsWord(2)], ["1 session", "2 sessions"]);
  assert.equal(projectsWord(1), "1 project");
  assert.equal(waitingWord(2), "2 waiting");
  assert.equal(moreWord(3), "+3");
  assert.equal(moreRowsWord(2), "+2 more");
  assert.equal(subagentWord(""), "subagent");
  assert.equal(subagentWord("Explore"), "Explore");
  assert.equal(rowDetail("", "Runs"), "Runs");
  assert.equal(rowDetail("Waiting in Claude App", "Runs"), "Waiting in Claude App");
  assert.equal(badgeTitle(3), "Projects, 3 waiting");
  assert.deepEqual([pinTitle(true), pinTitle(false)], ["Unpin", "Pin"]);
});

test("the big card's step line falls back to the state's words", () => {
  assert.equal(bigStepLine({ step: "", state: "approval" }), "waiting for you");
  assert.equal(bigStepLine({ step: "Runs", state: "approval" }), "Runs");
  assert.equal(STATE_WORDS.question, "has a question");
  assert.equal(STATE_WORDS.finished, "finished");
});

test("the dot's classes: the state, and a pulse only while the island is open and a card waits", () => {
  assert.equal(dotClass("approval", true), "pj-dot pj-approval pj-pulse");
  assert.equal(dotClass("question", true), "pj-dot pj-question pj-pulse");
  assert.equal(dotClass("question", false), "pj-dot pj-question");
  assert.equal(dotClass("working", true), "pj-dot pj-working");
});

test("the empty and help words are the Mac's", () => {
  assert.equal(EMPTY_SCREEN, "No Claude Code session is running.");
  assert.equal(EMPTY_SETTINGS, "No Claude Code project is running. Each one is listed here while it runs, and keeps the cat you give it.");
  assert.equal(CATS_HELP, "Each project wears the cat you give it, by its folder's name; up to 256 projects keep one. A project without one gets a cat that is not the Main cat.");
  assert.equal(CLAUDE_COLOR, "#F5F6F8");
});

test("projectStep: the tool's words, the path reduced to its last part, never a command or a query; none for AskUserQuestion", () => {
  assert.equal(projectStep("Bash", { command: "x" }), "Runs");
  assert.equal(projectStep("Edit", { file_path: "C:\\a\\b.ts" }), "Edits · b.ts");
  assert.equal(projectStep("Grep", { pattern: "SECRET", path: "/home/dev/src" }), "Searches · src");
  assert.equal(projectStep("WebSearch", { query: "q" }), "Web search");
  assert.equal(projectStep("AskUserQuestion", {}), null);
  assert.equal(projectStep("", {}), null);
  assert.equal(projectStep(undefined, null), null);
});

test("projectKittens keeps the order and the states, with no session and no leaving time", () => {
  const kittens = projectKittens([{ id: "k1", type: "Explore", state: "approval" }, { id: "k2", type: "Plan", state: "working" }]);
  assert.deepEqual(kittens.map((k) => [k.id, k.type, k.state, k.born, k.last, k.session, k.until]), [["k1", "Explore", "approval", 0, 0, null, null], ["k2", "Plan", "working", 0, 0, null, null]]);
  assert.deepEqual(kittenOrder(kittens).map((k) => k.id), ["k1", "k2"], "an approval is shown first");
});

test("projectKittens: the shown order is kittenOrder's: an approval first whatever the input, ties show the later subagent first", () => {
  const reversed = projectKittens([{ id: "k2", type: "Plan", state: "working" }, { id: "k1", type: "Explore", state: "approval" }]);
  assert.deepEqual(kittenOrder(reversed).map((k) => k.id), ["k1", "k2"], "the approval leads, not the input order");
  const ties = projectKittens([{ id: "k1", type: "Explore", state: "working" }, { id: "k2", type: "Plan", state: "working" }]);
  assert.deepEqual(kittenOrder(ties).map((k) => k.id), ["k2", "k1"], "two working ones: the later input is first");
});

test("projectTask is the project's pill: its id, name, colour, state and the Claude Code source, with no steps", () => {
  const t = projectTask({ id: "p-1", name: "app", state: "approval" });
  assert.deepEqual([t.id, t.name, t.color, t.state, t.steps, t.source], ["p-1", "app", CLAUDE_COLOR, "approval", [], "claudeCode"]);
});

test("projectCatRows: live projects first, one row per folder name; then the stored names that no live project has", () => {
  const rows = projectCatRows(
    [{ catKey: "b", name: "b — x" }, { catKey: "a", name: "a" }, { catKey: "b", name: "b — y" }],
    { c: "momo", a: "oreo", "x/y": "momo" },
    "shrimpy",
  );
  assert.notEqual(rows[0].cat, "shrimpy", "a project that is not stored never takes the Main cat");
  assert.deepEqual(rows, [
    { catKey: "b", name: "b — x", cat: P.projectCatOf("b", { c: "momo", a: "oreo" }, "shrimpy").cat, stored: false, live: true },
    { catKey: "a", name: "a", cat: "oreo", stored: true, live: true },
    { catKey: "c", name: "c", cat: "momo", stored: true, live: false },
  ]);
});

test("a 60,000-slash file_path (a run of separators before a name) gives its step in well under 500 ms, and the step is bounded", () => {
  const slashes = "/".repeat(60_000) + "x";
  const t0 = performance.now();
  const step = projectStep("Edit", { file_path: slashes });
  const elapsed = performance.now() - t0;
  assert.ok(elapsed < 500, `took ${elapsed.toFixed(1)} ms`);
  assert.ok(step !== null && Array.from(step).length <= 80, "bounded to the step's cap");
});

test("a tool named like an Object.prototype key shows its own name, never inherited text", () => {
  for (const tool of ["constructor", "__proto__"]) {
    const step = projectStep(tool, {});
    assert.equal(step, tool, `${tool} shows verbatim`);
    assert.doesNotMatch(step, /function|\[object/);
  }
});
