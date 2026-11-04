import test from "node:test";
import assert from "node:assert/strict";
import {
  GRID_CAPACITY, PANEL_COLUMNS, PANEL_EXTRA, SCREEN_H, SCREEN_LEADING, SCREEN_BOTTOM, PIN_MENU_RELEASE_MS,
  gridCells, panelCells, cellKey, usesProjects, chevronShown, peekLineCapacity, cut, pillNameParts,
} from "../../src/projects/cells.ts";

// The island's cells: the Mac's ProjectsLayout rules (ProjectsLayoutTests), pure.

test("the grid: projects first, then the other pills while they fit; past the capacity a +N cell", () => {
  assert.deepEqual(gridCells([], ["s1", "s2"]), [{ kind: "pill", id: "s1" }, { kind: "pill", id: "s2" }]);
  assert.deepEqual(gridCells(["a", "b"], ["s1", "s2", "s3"]), [{ kind: "project", id: "a" }, { kind: "project", id: "b" }, { kind: "pill", id: "s1" }, { kind: "pill", id: "s2" }]);
  assert.deepEqual(gridCells(["a", "b", "c", "d", "e"], ["s1"]), [{ kind: "project", id: "a" }, { kind: "project", id: "b" }, { kind: "project", id: "c" }, { kind: "more", count: 2 }]);
  const seven = gridCells(["a", "b", "c", "d", "e", "f", "g"], []);
  assert.equal(seven.length, 4);
  assert.deepEqual(seven.slice(0, 3), [{ kind: "project", id: "a" }, { kind: "project", id: "b" }, { kind: "project", id: "c" }]);
  assert.deepEqual(seven.at(-1), { kind: "more", count: 4 });
});

test("the panel: one row of three, the same rule without pills", () => {
  assert.deepEqual(panelCells(["a", "b", "c"]), [{ kind: "project", id: "a" }, { kind: "project", id: "b" }, { kind: "project", id: "c" }]);
  assert.deepEqual(panelCells(["a", "b", "c", "d"]), [{ kind: "project", id: "a" }, { kind: "project", id: "b" }, { kind: "more", count: 2 }]);
});

test("a cell's key: a project or a pill by its id, the +N cell one key whatever its count", () => {
  assert.equal(cellKey({ kind: "project", id: "a" }), "p:a");
  assert.equal(cellKey({ kind: "more", count: 3 }), "more");
  assert.equal(cellKey({ kind: "more", count: 9 }), "more");
  assert.equal(cellKey({ kind: "pill", id: "s1" }), "pill:s1");
});

test("usesProjects: the projects layout, a live project, the Claude pill or no focus, and no Two cats", () => {
  assert.equal(usesProjects("projects", null, 1, false), true);
  assert.equal(usesProjects("projects", "integration_claude", 1, false), true);
  assert.equal(usesProjects("projects", "agent_codex", 1, false), false);
  assert.equal(usesProjects("projects", null, 0, false), false);
  assert.equal(usesProjects("projects", null, 1, true), false);
  assert.equal(usesProjects("agents", null, 1, false), false);
});

test("chevronShown: the agents layout, the Claude pill focused, a live project, and no Two cats", () => {
  assert.equal(chevronShown("agents", "integration_claude", 1, false), true);
  assert.equal(chevronShown("agents", null, 1, false), false);
  assert.equal(chevronShown("agents", "integration_claude", 1, true), false);
  assert.equal(chevronShown("projects", "integration_claude", 1, false), false);
});

test("the peek's line capacity: the Mac's card is three lines, a taller one four", () => {
  assert.equal(peekLineCapacity(98), 3);
  assert.equal(peekLineCapacity(108), 4);
});

test("cut: all lines when they fit; else one less than the capacity and the rest as more", () => {
  assert.deepEqual(cut(3, 3), { shown: 3, more: 0 });
  assert.deepEqual(cut(5, 3), { shown: 2, more: 3 });
  assert.deepEqual(cut(1, 0), { shown: 0, more: 1 });
});

test("pillNameParts: the folder before the first ' — ', the detail after it, none when empty or when there is no split", () => {
  assert.deepEqual(pillNameParts("notchmeow — Code"), { folder: "notchmeow", detail: "Code" });
  assert.deepEqual(pillNameParts("notchmeow — Code · 2"), { folder: "notchmeow", detail: "Code · 2" });
  assert.deepEqual(pillNameParts("site — "), { folder: "site", detail: null });
  assert.deepEqual(pillNameParts(" — x"), { folder: " — x", detail: null });
  assert.deepEqual(pillNameParts("app"), { folder: "app", detail: null });
});

test("the layout constants are the Mac's", () => {
  assert.deepEqual([GRID_CAPACITY, PANEL_COLUMNS, PANEL_EXTRA, SCREEN_H, SCREEN_LEADING, SCREEN_BOTTOM, PIN_MENU_RELEASE_MS], [4, 3, 92, 240, 80, 22, 500]);
});

test("the grid at the capacity: 4 projects leave no room for a pill and no +N; 3 projects and 1 pill fit; 3 projects and 3 pills show only 1 pill", () => {
  assert.deepEqual(gridCells(["a", "b", "c", "d"], ["s1"]), [{ kind: "project", id: "a" }, { kind: "project", id: "b" }, { kind: "project", id: "c" }, { kind: "project", id: "d" }]);
  assert.deepEqual(gridCells(["a", "b", "c"], ["s1"]), [{ kind: "project", id: "a" }, { kind: "project", id: "b" }, { kind: "project", id: "c" }, { kind: "pill", id: "s1" }]);
  assert.deepEqual(gridCells(["a", "b", "c"], ["s1", "s2", "s3"]), [{ kind: "project", id: "a" }, { kind: "project", id: "b" }, { kind: "project", id: "c" }, { kind: "pill", id: "s1" }]);
});
