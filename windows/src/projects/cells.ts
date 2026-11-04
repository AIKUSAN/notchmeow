// The island's cells and layout numbers: the Mac's ProjectsLayout rules (NotchBuddy/Sources/App/ProjectsLayout.swift), pure. Pure: no DOM, no timer.

import type { Layout } from "./core.ts";

export const GRID_CAPACITY = 4;
export const PANEL_COLUMNS = 3;
export const PANEL_EXTRA = 92;
export const SCREEN_H = 240;
export const SCREEN_LEADING = 80;
export const SCREEN_BOTTOM = 22;
export const PIN_MENU_RELEASE_MS = 500;

export type Cell = { kind: "project"; id: string } | { kind: "more"; count: number } | { kind: "pill"; id: string };

/** What a keyed list keys the cell by: a cell is its project (or pill), never its slot, and the "+N" cell is one cell whatever its count. */
export function cellKey(c: Cell): string {
  if (c.kind === "project") return "p:" + c.id;
  if (c.kind === "more") return "more";
  return "pill:" + c.id;
}

/** The Claude-only card: the projects first (the caller orders them), then the other pills while they fit; past the capacity the last cell is "+N" for the rest. */
export function gridCells(projects: readonly string[], otherPills: readonly string[], capacity: number = GRID_CAPACITY): Cell[] {
  if (projects.length <= capacity) {
    return [...projects.map((id): Cell => ({ kind: "project", id })), ...otherPills.slice(0, Math.max(0, capacity - projects.length)).map((id): Cell => ({ kind: "pill", id }))];
  }
  return [...projects.slice(0, capacity - 1).map((id): Cell => ({ kind: "project", id })), { kind: "more", count: projects.length - (capacity - 1) }];
}

/** The expanded section: one row of `columns`, the same rule as the grid without pills. */
export function panelCells(projects: readonly string[], columns: number = PANEL_COLUMNS): Cell[] {
  if (projects.length <= columns) return projects.map((id): Cell => ({ kind: "project", id }));
  return [...projects.slice(0, columns - 1).map((id): Cell => ({ kind: "project", id })), { kind: "more", count: projects.length - (columns - 1) }];
}

/** The Claude-only card replaces the left and right cards only in the projects layout, with the Claude pill (or no focus) and at least one live project. Two cats mode keeps the overview. */
export function usesProjects(layout: Layout, focusId: string | null, projectCount: number, twoCats: boolean): boolean {
  if (twoCats || projectCount < 1 || layout !== "projects") return false;
  return focusId === null || focusId === "integration_claude";
}

/** The chevron that opens the section under the two panels: the agents layout, the Claude pill focused, a live project, and no Two cats. */
export function chevronShown(layout: Layout, focusId: string | null, projectCount: number, twoCats: boolean): boolean {
  return !twoCats && layout === "agents" && focusId === "integration_claude" && projectCount >= 1;
}

/** The lines a peek card holds: its height less the padding, the header and its spacing, plus one line spacing, over a line and its spacing. */
export function peekLineCapacity(cardH: number): number {
  return Math.floor((cardH - 2 * 10 - 16 - 6 + 2) / (14 + 2));
}

/** The lines a peek shows: all of them when they fit; else one less than the capacity, and the rest as "more". */
export function cut(lines: number, capacity: number): { shown: number; more: number } {
  if (lines <= capacity) return { shown: lines, more: 0 };
  const shown = Math.max(0, capacity - 1);
  return { shown, more: lines - shown };
}

/** A pill's name, split at its first " — ": the folder, and the detail after it. No split when there is no " — " after a first character; an empty detail is no detail. */
export function pillNameParts(name: string): { folder: string; detail: string | null } {
  const at = name.indexOf(" — ");
  if (at <= 0) return { folder: name, detail: null };
  const detail = name.slice(at + 3);
  return { folder: name.slice(0, at), detail: detail === "" ? null : detail };
}
