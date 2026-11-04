// The words of the Projects view (ProjectsLayout.swift's, exact) and the small pure helpers the island and Settings draw with. Pure: no DOM, no timer.
// A word never holds a path: names, labels, steps and states only (the contract's privacy rule).

import { cleanProjectCats, cleanStep, projectCatOf } from "./core.ts";
import type { ProjectRow, StateWord, SubagentRow } from "./core.ts";
import { stepLabel } from "../core/steps.ts";
import type { AgentTask } from "../core/state.ts";
import type { Kitten } from "../cat/kittens.ts";

/** The words of the big card's state line, when a project has no step (CatIslandLayout.stateWords, for these five states). */
export const STATE_WORDS: Readonly<Record<StateWord, string>> = {
  approval: "waiting for you",
  question: "has a question",
  working: "working",
  finished: "finished",
  idle: "idle",
};

export const EMPTY_SCREEN = "No Claude Code session is running.";
export const EMPTY_SETTINGS = "No Claude Code project is running. Each one is listed here while it runs, and keeps the cat you give it.";
export const CATS_HELP = "Each project wears the cat you give it, by its folder's name; up to 256 projects keep one. A project without one gets a cat that is not the Main cat.";
/** The Claude Code pill's colour (state.ts INTEGRATION_AGENTS). */
export const CLAUDE_COLOR = "#F5F6F8";

/** A host as the words say it. */
export function hostWord(host: string): string {
  if (host === "claude-app") return "Claude App";
  if (host === "vscode") return "VS Code";
  return "Terminal";
}

/** "now", "N min ago" under an hour, then "N h ago" (whole hours). */
export function agoWord(min: number): string {
  if (min < 1) return "now";
  if (min < 60) return `${min} min ago`;
  return `${Math.floor(min / 60)} h ago`;
}

export const sessionsWord = (n: number): string => (n === 1 ? "1 session" : `${n} sessions`);
export const projectsWord = (n: number): string => (n === 1 ? "1 project" : `${n} projects`);
export const waitingWord = (n: number): string => `${n} waiting`;
export const moreWord = (n: number): string => `+${n}`;
export const moreRowsWord = (n: number): string => `+${n} more`;
/** A subagent's type, or "subagent" when it has none. */
export const subagentWord = (type: string): string => (type === "" ? "subagent" : type);
/** A row's second line: its note (the wait) when it has one, else its step. */
export const rowDetail = (note: string, step: string): string => (note === "" ? step : note);

/** The big card's step line: the project's step, else the state's words. */
export const bigStepLine = (p: Pick<ProjectRow, "step" | "state">): string => (p.step !== "" ? p.step : STATE_WORDS[p.state]);

/** The Projects menu-bar item's title for the waiting count. */
export const badgeTitle = (waiting: number): string => `Projects, ${waiting} waiting`;
export const pinTitle = (pinned: boolean): string => (pinned ? "Unpin" : "Pin");

/** A state dot's class: the state, and a pulse only while the island is open and a card waits. */
export function dotClass(state: StateWord, open: boolean): string {
  const waits = state === "approval" || state === "question";
  return `pj-dot pj-${state}` + (open && waits ? " pj-pulse" : "");
}

/**
 * The step a PreToolUse leaves on its session: the tool's words with its input reduced to the `path` and `file_path` keys (so Bash is "Runs"), cleaned as
 * the notch shows it. Null for AskUserQuestion, for a tool with no name, or when nothing is left.
 */
export function projectStep(tool: unknown, input: unknown): string | null {
  if (typeof tool !== "string" || tool === "" || tool === "AskUserQuestion") return null;
  const src = input !== null && typeof input === "object" && !Array.isArray(input) ? (input as Record<string, unknown>) : {};
  const reduced: Record<string, unknown> = {};
  for (const key of ["path", "file_path"]) if (typeof src[key] === "string") reduced[key] = src[key];
  const line = cleanStep(stepLabel(tool, reduced));
  return line === "" ? null : line;
}

/**
 * The subagent kittens of a project. The Mac's mapping (ProjectsViews.swift): born and last 0, no session, no leaving time. The order shown is kittenOrder's:
 * a kitten waiting on an approval first, then ties show the later subagent first.
 */
export function projectKittens(subs: readonly SubagentRow[]): Kitten[] {
  return subs.map((s) => ({ id: s.id, type: s.type, session: null, state: s.state, born: 0, last: 0, until: null }));
}

/** The pill a project is drawn as: its id, name, the Claude colour, its state, no steps, the Claude Code source. */
export function projectTask(p: Pick<ProjectRow, "id" | "name" | "state">): AgentTask {
  return { id: p.id, name: p.name, color: CLAUDE_COLOR, state: p.state, stepIndex: 0, steps: [], source: "claudeCode", isIntegration: false };
}

/** A live project for Settings: its folder name (the key of its cat) and the name the notch shows. */
export interface LiveProject { catKey: string; name: string }

/** One row of Settings' "Project cats". */
export interface CatRow { catKey: string; name: string; cat: string; stored: boolean; live: boolean }

/**
 * The live projects first, in their order, one row per folder name (two live projects with one name make one row, under the first name); then each stored
 * folder name that no live project has, in UTF-16 order, named by itself. A row's cat is the stored one, else the one the project gets with the Main cat
 * taken. Nothing is stored here.
 */
export function projectCatRows(live: readonly LiveProject[], stored: unknown, main: unknown): CatRow[] {
  const held = cleanProjectCats(stored);
  const seen = new Set<string>();
  const out: CatRow[] = [];
  for (const project of live) {
    if (seen.has(project.catKey)) continue;
    seen.add(project.catKey);
    const shown = projectCatOf(project.catKey, held, main);
    out.push({ catKey: project.catKey, name: project.name, cat: shown.cat, stored: shown.stored, live: true });
  }
  for (const key of Object.keys(held).sort()) {
    if (seen.has(key)) continue;
    out.push({ catKey: key, name: key, cat: held[key], stored: true, live: false });
  }
  return out;
}
