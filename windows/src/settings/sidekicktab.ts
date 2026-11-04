// The words and the example lines of the Sidekick tab in Settings (the Settings restyle spec's Sidekick section). Port of NotchBuddy/Sources/App/SettingsSidekick.swift.
// The four stuck kinds are the ones the sidekick rules rank; the switch reads on while at least one of them still shows. The example lines come from the core's own wording
// (`nudgeText`, `recapOf`) on a made-up session on a fixed clock: they never touch the live ledger and never carry a path. Pure. Tests: windows/scripts/settings-tests.

import { NUDGE_KINDS, nudgeText, recapOf } from "../sidekick/core.ts";
import type { NudgeKind, Session } from "../sidekick/core.ts";
import { KIND_LABELS } from "../sidekick/settings.ts";

/** The four stuck kinds, in the sidekick's order. */
export const STUCK_KINDS: readonly NudgeKind[] = NUDGE_KINDS;
/** Each stuck kind with its label, the words Settings → Sidekick shows (KIND_LABELS holds them once). */
export const STUCK_NAMES: readonly { kind: NudgeKind; label: string }[] = STUCK_KINDS.map((kind) => ({ kind, label: KIND_LABELS[kind] }));
export const PERMISSION_LINE = "Always on: it tells you what a permission would do.";
export const NOTHING_LEAVES = "Nothing leaves this computer unless you pick a cloud AI as your main AI.";
export const COMES_WITH_F3A = "Coming soon";

const MIN = 60_000;
const NOW = 10_000_000;

/** The stuck switch: off when all four are muted, on when none is, and on with "N of 4" still showing when some are muted. */
export function stuckSwitch(isMuted: (kind: string) => boolean): { on: boolean; detail: string | null } {
  const muted = STUCK_KINDS.filter((k) => isMuted(k)).length;
  if (muted === STUCK_KINDS.length) return { on: false, detail: null };
  if (muted === 0) return { on: true, detail: null };
  return { on: true, detail: `${STUCK_KINDS.length - muted} of ${STUCK_KINDS.length}` };
}

/** A made-up Claude Code session: quiet for 5 minutes, waiting for an OK, three edits in its last three minutes. */
function exampleSession(): Session {
  const files = ["app.ts", "lib.ts", "main.ts"];
  return {
    key: "integration_claude|example", agentId: "integration_claude", sessionId: "example",
    startedAt: NOW - 20 * MIN, lastEventAt: NOW - 5 * MIN, endedAt: null, state: "approval", last: "", project: "my-app",
    ring: files.map((f, i) => ({ at: NOW - (files.length - i) * MIN, kind: "tool", tool: "Edit", target: f, file: f, key: `Edit#${i}`, ok: true })),
    pendingApprovalAt: NOW - 30_000, pendingKey: null, subagents: {}, nudgedAt: null,
  };
}

const isStuck = (kind: string): kind is NudgeKind => (STUCK_KINDS as readonly string[]).includes(kind);

/** One example line for a kind (`recap` or a stuck kind), built by the core's rules; null for any other kind. */
export function example(kind: string): string | null {
  const s = exampleSession();
  if (kind === "recap") return recapOf({ awaySince: NOW - 10 * MIN, now: NOW, sessions: [s] })?.lines[0] ?? null;
  if (!isStuck(kind)) return null;
  return nudgeText({ kind, reasonId: "example", key: s.key, agentId: s.agentId }, { sessions: [s] }, NOW, { platform: "windows" });
}
