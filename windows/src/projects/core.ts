// The Projects contract's rules, typed (docs/PROJECTS-CONTRACT.md). The rules themselves are shared/projects-core.js, copied by scripts/gen-projects-ts.mjs into
// core.generated.ts; this file gives them their types and nothing else. Pure: no clock, no network, no files. Every rule is given the time it needs.
// Loaded by the plain-Node checks (npm run check:projects): erasable TypeScript only, relative imports with the `.ts` extension.

import { ProjectsCore } from "./core.generated.ts";

export type StateWord = "approval" | "question" | "working" | "finished" | "idle";
export type Host = "claude-app" | "vscode" | "terminal";
export type Layout = "projects" | "agents";

export interface ProjectEvent {
  at: number; agent: string; kind: string; sessionId: string; cwd: string; subagentId: string; subagentType: string; fromApp: boolean; termProgram: string; bundleId: string; waitIn: string; stepped: boolean;
}
export interface PendingAsk { by: string; kind: "approval" | "question"; at: number; inApp: boolean; waitIn: string }
export interface RegSubagent { id: string; type: string; state: string; born: number; last: number }
export interface RegSession {
  id: string; cwd: string; root: string; worktree: string; seq: number; startedAt: number; lastAt: number; run: "idle" | "working" | "finished"; finishedAt: number | null;
  pending: PendingAsk[]; fromApp: boolean; termProgram: string; bundleId: string; subagents: RegSubagent[];
}
export interface Registry { version: 1; home: string; sessions: RegSession[]; otherAgentSeen: boolean; nextSeq: number }
export interface SessionState { state: StateWord; dim: boolean; gone: boolean; waitingInApp: boolean }
export interface SubagentRow { id: string; type: string; state: "approval" | "working" }
export interface SessionRow {
  id: string; role: "main" | "side"; label: string; state: StateWord; dim: boolean; waitingInApp: boolean; note: string; step: string; host: Host; lastAt: number; agoMin: number; subagents: SubagentRow[];
}
export interface ProjectRow {
  id: string; name: string; catKey: string; cat: string; state: StateWord; dim: boolean; waiting: number; sessionCount: number; lastAt: number; agoMin: number; step: string; host: Host; sessions: SessionRow[];
}
export interface ProjectsView { projects: ProjectRow[]; waiting: number; sessionCount: number; otherAgentSeen: boolean }
export interface ViewOpts { steps?: Record<string, string>; projectCats?: unknown; mainCat?: unknown }
export interface BigCard { project: string | null; pinned: string | null; clicked: string | null }

export const VERSION = ProjectsCore.VERSION as number;
export const QUIET_IDLE_MS = ProjectsCore.QUIET_IDLE_MS as number;
export const DIM_MS = ProjectsCore.DIM_MS as number;
export const REMOVE_MS = ProjectsCore.REMOVE_MS as number;
export const FINISHED_MS = ProjectsCore.FINISHED_MS as number;
export const APP_WAIT_MS = ProjectsCore.APP_WAIT_MS as number;
export const CARD_APPROVAL_MS = ProjectsCore.CARD_APPROVAL_MS as number;
export const CARD_QUESTION_MS = ProjectsCore.CARD_QUESTION_MS as number;
export const PEEK_DWELL_MS = ProjectsCore.PEEK_DWELL_MS as number;
export const AGO_TICK_MS = ProjectsCore.AGO_TICK_MS as number;
export const SUBAGENTS_MAX = ProjectsCore.SUBAGENTS_MAX as number;
export const SESSIONS_MAX = ProjectsCore.SESSIONS_MAX as number;
export const NAME_MAX = ProjectsCore.NAME_MAX as number;
export const STEP_MAX = ProjectsCore.STEP_MAX as number;
export const PROJECT_CATS_MAX = ProjectsCore.PROJECT_CATS_MAX as number;
export const CWD_MAX_BYTES = ProjectsCore.CWD_MAX_BYTES as number;
export const PENDING_MAX = ProjectsCore.PENDING_MAX as number;
export const APP_WAIT_LABEL = ProjectsCore.APP_WAIT_LABEL as string;
export const HOME_NAME = ProjectsCore.HOME_NAME as string;
export const STATES = ProjectsCore.STATES as readonly StateWord[];
export const CAT_IDS = ProjectsCore.CAT_IDS as readonly string[];

export const fnv1a = ProjectsCore.fnv1a as (s: string) => string;
export const normPath = ProjectsCore.normPath as (cwd: unknown) => string;
export const projectOf = ProjectsCore.projectOf as (cwd: unknown, roots: unknown, home: unknown) => { root: string; worktree: string } | null;
export const projectNames = ProjectsCore.projectNames as (roots: unknown, home: unknown) => { root: string; name: string; catKey: string }[];
export const rolesOf = ProjectsCore.rolesOf as (sessions: unknown) => { id: string; role: "main" | "side"; label: string }[];
export const sessionOrder = ProjectsCore.sessionOrder as (rows: unknown) => string[];
export const projectEventFrom = ProjectsCore.projectEventFrom as (payload: unknown, now: number, waitIn?: unknown) => ProjectEvent | null;
export const emptyRegistry = ProjectsCore.emptyRegistry as (home?: unknown) => Registry;
export const registryApply = ProjectsCore.registryApply as (registry: Registry, ev: ProjectEvent | null) => Registry;
export const registryPrune = ProjectsCore.registryPrune as (registry: Registry, now: number) => Registry;
export const sessionStateAt = ProjectsCore.sessionStateAt as (session: unknown, now: unknown) => SessionState;
export const projectStateOf = ProjectsCore.projectStateOf as (states: unknown) => StateWord;
export const cleanStep = ProjectsCore.cleanStep as (text: unknown) => string;
export const waitLabel = ProjectsCore.waitLabel as (host?: unknown) => string;
export const projectsView = ProjectsCore.projectsView as (registry: Registry, now: unknown, opts?: ViewOpts) => ProjectsView;
export const projectOrder = ProjectsCore.projectOrder as <T>(projects: T[]) => T[];
export const bigCardOf = ProjectsCore.bigCardOf as (projects: unknown, pinned: unknown, clicked: unknown) => BigCard;
export const waitingCount = ProjectsCore.waitingCount as (projects: unknown) => number;
export const claudeOnly = ProjectsCore.claudeOnly as (activePills: unknown, otherAgentSeen: unknown) => boolean;
export const islandLayout = ProjectsCore.islandLayout as (current: unknown, claudeOnlyNow: unknown, open: unknown) => Layout;
export const cleanProjectCats = ProjectsCore.cleanProjectCats as (raw: unknown) => Record<string, string>;
export const projectCatOf = ProjectsCore.projectCatOf as (catKey: unknown, projectCats: unknown, mainCat: unknown) => { cat: string; stored: boolean };
export const agoOf = ProjectsCore.agoOf as (now: unknown, lastAt: unknown) => number;
