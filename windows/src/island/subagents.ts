// Subagent hook events → kitten events (sub-project B, spec §3). The hook handlers (hooks.ts) call `kittenEventOf` for every hook event and give what comes back to the
// pill's kitten list (`State.kittenEvent`). Pure, so the plain-Node checks (npm run check:cat) can load it. The table is docs/CAT-CONTRACT.md "Kittens":
//
//   SubagentStart (agent_id, agent_type, session_id)     start       a kitten, working
//   PreToolUse, PostToolUse with an agent_id            tool        searching for a search tool, else working (no agent_id: the parent's own tool, no kitten event)
//   PermissionRequest with an agent_id                  permission  approval (its answer is `resolved`, sent by the approval's paths)
//   SubagentStop                                        stop        a happy blink of 0.6 s, then gone
//   the parent's Stop, StopFailure, and SessionEnd      end         every kitten of that session goes (an event with an agent_id is a subagent's own, not the parent's)
//
// Codex has no hooks on Windows and Linux, so no Codex kittens here; Gemini CLI and Antigravity send no subagent events.

import type { KittenEvent } from "../cat/kittens.ts";

const isId = (v: unknown): v is string => typeof v === "string" && v.length > 0 && v.length <= 128;

/** The kitten event a hook event means, at time `t` (ms, the clock the kitten lists use), or null when it is not one. `payload` is the hook JSON as the relay sent it. */
export function kittenEventOf(payload: unknown, t: number): KittenEvent | null {
  if (payload === null || typeof payload !== "object" || Array.isArray(payload) || typeof t !== "number" || !Number.isFinite(t)) return null;
  const p = payload as Record<string, unknown>, id = isId(p.agent_id) ? p.agent_id : null;
  switch (p.hook_event_name) {
    case "SubagentStart":
      return id === null ? null : { type: "start", id, ...(typeof p.agent_type === "string" ? { agentType: p.agent_type } : {}), ...(isId(p.session_id) ? { session: p.session_id } : {}), t };
    case "SubagentStop":
      return id === null ? null : { type: "stop", id, t };
    case "PreToolUse":
    case "PostToolUse":
      return id === null ? null : { type: "tool", id, ...(typeof p.tool_name === "string" ? { tool: p.tool_name } : {}), t };
    case "PermissionRequest":
      return id === null ? null : { type: "permission", id, t };
    case "Stop":
    case "StopFailure":
    case "SessionEnd":
      return id !== null ? null : { type: "end", ...(isId(p.session_id) ? { session: p.session_id } : {}), t };
    default:
      return null;
  }
}
