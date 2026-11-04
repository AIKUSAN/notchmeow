// The sidekick contract's rules, typed (docs/SIDEKICK-CONTRACT.md). The rules themselves are shared/sidekick-core.js, copied by scripts/gen-sidekick-ts.mjs into
// core.generated.ts; this file gives them their types and nothing else. Pure: no clock, no network, no files. Every rule is given the time it needs.
// Loaded by the plain-Node checks (npm run check:sidekick): erasable TypeScript only, relative imports with the `.ts` extension.

import { SidekickCore } from "./core.generated.ts";

export type Risk = "low" | "medium" | "high";
export interface Explained { risk: Risk; reasonId: string; line: string; target: string }

export type EventKind =
  | "sessionStart" | "prompt" | "preTool" | "question" | "tool" | "failure" | "approvalAsked" | "approvalAnswered"
  | "stop" | "stopFailure" | "subagentStart" | "subagentStop" | "sessionEnd" | "notification";
export interface SidekickEvent {
  at: number; agentId: string; sessionId: string; kind: EventKind; name: string; tool: string; target: string; file: string; key: string; ok: boolean; project: string; subagentId: string;
}
export interface RingEntry { at: number; kind: string; tool: string; target: string; file: string; key: string; ok: boolean }
export interface Session {
  key: string; agentId: string; sessionId: string; startedAt: number; lastEventAt: number; endedAt: number | null; state: string; last: string; project: string;
  ring: RingEntry[]; pendingApprovalAt: number | null; pendingKey: string | null; subagents: Record<string, number>; nudgedAt: number | null;
}
export interface Ledger { sessions: Session[] }

export type NudgeKind = "stuck.loop" | "stuck.errors" | "stuck.waiting" | "stuck.silent";
export type NoteKind = "recap" | NudgeKind;
export interface Nudge { kind: NudgeKind; reasonId: string; key: string; agentId: string }
export type Platform = "mac" | "windows" | "linux";
/** What `stuckStep` and `nudgeText` are told about the world. All false (and the Mac) when absent. */
export interface StuckContext { ratelimit?: boolean; away?: boolean; cardShown?: boolean; platform?: Platform; muted?: NoteKind[] }
export interface StuckResult { nudge: Nudge | null; nextAt: number | null }

export interface RecapFacts {
  agent: string; agentId: string; project: string; steps: number; stepsAtLeast: boolean; files: string[]; more: number; errors: number; approvals: number; end: string; quietMinutes: number;
}
export interface Recap { lines: string[]; facts: RecapFacts[] }
export interface Snapshot { awaySince?: number; now: number; sessions: Session[] }
export interface StatusQuestion { matched: boolean; agentId: string | null }

export interface PresenceState { reasons: string[]; awaySince: number | null; wasAway: boolean }
export type PresenceSignal =
  | { type: "lock" | "unlock" | "sleep" | "wake" | "displayOff" | "displayOn" }
  | { type: "idle"; seconds: number };
export interface PresenceResult { state: PresenceState; back: false | { back: true; awaySince: number; awayMs: number } }

export type Dismissals = Record<NoteKind, number>;
/** The stored `sidekick` object: the master switch, the local-voice switch and the dismissal counts. */
export interface SidekickSettings { on: boolean; local: boolean; dismissals: Dismissals }

export interface ShowInput {
  on?: boolean; kind: string; dismissals?: unknown; away?: boolean; ratelimit?: boolean; card?: "approval" | "question" | null; ownCard?: boolean; inputFocused?: boolean;
  visible?: { kind: string; seen: boolean } | null; lastShownAt?: number | null; now: number; nudged?: boolean; recapGiven?: boolean;
}
export interface ShowResult { show: boolean; reason: string; replace: boolean }

export const explain = SidekickCore.explain as (agent: string, tool: string, toolInput: unknown, cwd: string, home: string) => Explained;
export const eventFrom = SidekickCore.eventFrom as (payload: unknown, now: number, opts?: { codex?: boolean }) => SidekickEvent | null;
export const approvalAnsweredEvent = SidekickCore.approvalAnsweredEvent as (agentId: string, sessionId: string, now: number) => SidekickEvent;
export const emptyLedger = SidekickCore.emptyLedger as () => Ledger;
export const ledgerApply = SidekickCore.ledgerApply as (ledger: Ledger, event: SidekickEvent) => Ledger;
export const ledgerPrune = SidekickCore.ledgerPrune as (ledger: Ledger, now: number) => Ledger;
export const liveSessions = SidekickCore.liveSessions as (ledger: Ledger) => Session[];
export const aliveSubagents = SidekickCore.aliveSubagents as (session: Session) => number;
export const stuckStep = SidekickCore.stuckStep as (ledger: Ledger, now: number, ctx?: StuckContext) => StuckResult;
export const markNudged = SidekickCore.markNudged as (ledger: Ledger, key: string, now: number) => Ledger;
export const nudgeText = SidekickCore.nudgeText as (nudge: Nudge, ledger: Ledger, now: number, ctx?: StuckContext) => string;
export const recapOf = SidekickCore.recapOf as (snapshot: Snapshot) => Recap | null;
export const statusOf = SidekickCore.statusOf as (snapshot: Snapshot, agentId?: string | null) => Recap;
export const matchStatusQuestion = SidekickCore.matchStatusQuestion as (text: string) => StatusQuestion;
export const cleanDismissals = SidekickCore.cleanDismissals as (raw: unknown) => Dismissals;
export const dismiss = SidekickCore.dismiss as (state: unknown, kind: string) => Dismissals;
export const muted = SidekickCore.muted as (state: unknown, kind: string) => boolean;
export const unmute = SidekickCore.unmute as (state: unknown, kind: string) => Dismissals;
export const mute = SidekickCore.mute as (state: unknown, kind: string) => Dismissals;
export const cleanSidekickSettings = SidekickCore.cleanSidekickSettings as (raw: unknown) => SidekickSettings;
export const presenceInit = SidekickCore.presenceInit as () => PresenceState;
export const presenceStep = SidekickCore.presenceStep as (state: PresenceState | null, signal: PresenceSignal, now: number) => PresenceResult;
export const shouldShow = SidekickCore.shouldShow as (input: ShowInput) => ShowResult;
export const acceptNicerLine = SidekickCore.acceptNicerLine as (line: unknown, facts: unknown) => boolean;
export const agentName = SidekickCore.agentName as (agentId: string) => string;
export const baseName = SidekickCore.baseName as (path: string) => string;

export const REASONS = SidekickCore.REASONS as readonly { id: string; risk: Risk; line: string }[];
export const STUCK = SidekickCore.STUCK as { LOOP_CALLS: number; LOOP_SAME: number; WINDOW_MS: number; ERRORS: number; WAIT_MS: number; SILENT_MS: number; SILENT_PRE_MS: number; KITTEN_MS: number; GIVE_UP_MS: Record<Platform, number> };
export const RECAP = SidekickCore.RECAP as { MIN_AWAY_MS: number; MAX_LINES: number; MAX_FILES: number; STATUS_FINISHED_MS: number };
export const NUDGE_KINDS = SidekickCore.NUDGE_KINDS as readonly NudgeKind[];
export const DISMISS_KINDS = SidekickCore.DISMISS_KINDS as readonly NoteKind[];
export const MUTE_AT = SidekickCore.MUTE_AT as number;
export const IDLE = SidekickCore.IDLE as { AWAY_S: number; BACK_S: number };
export const HOLD_MS = SidekickCore.HOLD_MS as { nudge: number; recap: number };
export const NOTE_GAP_MS = SidekickCore.NOTE_GAP_MS as number;
export const RING_MAX = SidekickCore.RING_MAX as number;
