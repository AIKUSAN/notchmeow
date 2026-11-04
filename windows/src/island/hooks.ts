// Claude Code hook events → island state.
// Port of HookServer.processEvent / processPermissionRequest from the macOS app.
// Difference from macOS: no terminal filter. On Windows the hook fires from any
// terminal (Windows Terminal, VS Code, PowerShell…) and all of them are handled.

import { Bridge, IS_TAURI, onEvent } from "../core/bridge";
import { routeHook } from "../core/claude.ts";
import { Sound } from "../core/sound";
import { State } from "../core/state";
import { toolState } from "../cat/base.ts";
import { agentColor, agentPillName } from "../core/pills.ts";
import { isClaudeDesktopTag } from "../core/openagent.ts";
import { FOREGROUND_WAIT_MS, focusEnabled, focusSessionKey, stepBackOrNone } from "../core/focusaware.ts";
import type { FocusMark } from "../core/focusaware.ts";
import { Hub } from "../sidekick/hub.ts";
import { kittenEventOf } from "./subagents.ts";
import { StopTimers } from "./stoptimers.ts";
import { approvalTarget, lastPathComponent, stepLabel } from "../core/steps.ts";
import type { Island } from "./island";

const CLAUDE_ID = "integration_claude";

/** Clears the approval card if no decision was made before the hook gave up. */
let pendingTimeout: number | null = null;

/** The same for each request waiting on a chat's own card: after this the terminal has taken over. */
const chatTimeouts = new Map<string, number>();

/** The return to idle that Stop arms, per pill: the next turn cancels it, or it would flip the pill to idle in the middle of that turn. */
const stopTimers = new StopTimers();

/** The part of a hook event the island reads (the relay forwards the whole JSON). */
export interface HookPayload {
  hook_event_name?: string;
  request_id?: string;
  session_id?: string;
  cwd?: string;
  message?: string;
  /** UserPromptSubmit carries `prompt`; `message` belongs to Notification/Stop. */
  prompt?: string;
  tool_name?: string;
  tool_input?: Record<string, unknown>;
  /** Optional agent tag: lowercase, digits and hyphens, ≤ 24 chars. */
  nm_agent?: string;
  /** Hook events fired inside a subagent carry its id and type (Claude Code); each subagent is a kitten of its parent's pill. */
  agent_id?: string;
  agent_type?: string;
}

/** Same rule as HookServer.validateAgent on macOS. "claude" is reserved. */
function validateAgent(raw: string | undefined): string | null {
  if (!raw || raw.length > 24 || raw === "claude") return null;
  if (!/^[a-z0-9-]+$/.test(raw)) return null;
  return raw;
}

const PROJECT_ALIASES: Record<string, string> = {
  "notch-buddy": "Notch Buddy",
  notchbuddy: "Notch Buddy",
  notch_buddy: "Notch Buddy",
};

function aliasProjectName(name: string): string {
  return PROJECT_ALIASES[name.toLowerCase()] ?? name;
}

function upsert(projectName: string, cwd: string) {
  const t = State.tasks.find((x) => x.id === CLAUDE_ID);
  if (!t) return;
  t.name = projectName;
  if (cwd) t.sessionCwd = cwd;
}

function clearSession() {
  const t = State.tasks.find((x) => x.id === CLAUDE_ID);
  if (!t) return;
  t.steps = [];
  t.stepIndex = 0;
  t.name = "Claude Code";
  t.pillBadge = null;
}

export function registerHookHandlers(island: Island) {
  void onEvent<HookPayload>("hook", (payload) => takeHook(island, payload));
}

/** The pin was made by a chat's card (the island was not pinned before it): only such a pin is released with the card. */
let chatMadePin = false;
/** For the paths that have no island of their own (Stop, a new chat): set by the first chat request. */
let islandRef: Island | null = null;

/** Pins the island for the chat's card. A pin the user made stays theirs, and the card's going does not release it. */
function holdIslandForChatCard(island: Island) {
  chatMadePin = !State.isPinned;
  State.isPinned = true;
  island.holdOpen();
}

/** The queue is empty: release the pin the card made, unless the user's own approval is still waiting on it. */
function releaseChatPin() {
  if (State.chatApprovals.length > 0 || !chatMadePin) return;
  chatMadePin = false;
  if (State.pendingApproval) return;
  State.isPinned = false;
  islandRef?.dropPin();
}

/** Opens the chat on the card: switch the view when the island is open, else open it there. */
function openChatForCard(island: Island) {
  if (State.mode === "expanded") island.setView("prompt");
  else island.alert("prompt");
}

/**
 * The user's own approval was just resolved (their paths clear the pin and change the view): a chat card still queued
 * comes back, pinned and on screen, unless another approval of the user's is waiting. Never switches the view away from
 * the user's own waiting approval.
 */
export function resurfaceChatApproval(island: Island) {
  if (!State.chatApprovals.front || State.pendingApproval) return;
  holdIslandForChatCard(island);
  openChatForCard(island);
  State.notify();
}

/** Hands every waiting request of a chat back to Claude Code (it refuses those steps) and takes the card away. */
export function releaseChatApprovals(sessionId?: string) {
  for (const waiting of State.chatApprovals.removeAll(sessionId)) {
    window.clearTimeout(chatTimeouts.get(waiting.requestId));
    chatTimeouts.delete(waiting.requestId);
    if (waiting.requestId) void Bridge.approvalDecline(waiting.requestId);
  }
  releaseChatPin();
  State.notify();
}

/**
 * Allow or Deny on the chat's card. `requestId` is the card the click was on: when it is no longer the front card (it
 * timed out, and the next one is a step the user has not seen), the click is ignored.
 */
export function decideChatApproval(decision: "allow" | "deny", requestId: string) {
  if (State.chatApprovals.front?.requestId !== requestId) return;
  const waiting = State.chatApprovals.popFront();
  if (!waiting) return;
  window.clearTimeout(chatTimeouts.get(waiting.requestId));
  chatTimeouts.delete(waiting.requestId);
  if (waiting.requestId) void Bridge.approvalDecision(waiting.requestId, decision);
  releaseChatPin();
  State.notify();
}

/**
 * A request from a chat's own Claude Code run. Its card is in that chat, never a pill, and it never touches the one
 * pending approval of the user's own sessions. Nothing runs without a click: when the app does not answer, Claude Code
 * refuses the step. Everything else a chat's run sends is not a session: the chat's own stream already shows its steps.
 */
function handleChatHook(island: Island, payload: HookPayload) {
  if (payload.hook_event_name !== "PermissionRequest") return;
  islandRef = island;
  const requestId = payload.request_id ?? "";
  const tool = payload.tool_name ?? "Tool";
  // A chat's run cannot be asked a question on the island: hand it back, Claude Code carries on without.
  if (tool === "AskUserQuestion") {
    if (requestId) void Bridge.approvalDecline(requestId);
    return;
  }
  const first = State.chatApprovals.length === 0;
  State.chatApprovals.push({
    requestId,
    sessionId: payload.session_id ?? "",
    tool,
    command: approvalTarget(tool, payload.tool_input ?? {}),
  });
  // The relay's short ack window closes in 800 ms; everything above is synchronous.
  if (requestId) void Bridge.approvalAck(requestId);
  if (requestId) {
    chatTimeouts.set(requestId, window.setTimeout(() => {
      State.chatApprovals.remove(requestId);
      chatTimeouts.delete(requestId);
      releaseChatPin();
      State.notify();
    }, 110_000));
  }
  if (first) {
    Sound.play("approval");
    holdIslandForChatCard(island);
    // The user's own approval is on screen: the card waits behind it and comes back when that is answered.
    if (!State.pendingApproval) openChatForCard(island);
  }
  State.notify();
}

/** The frontmost app's name on the dev server (setDevForeground); on the app it is read through Bridge.foregroundApp. */
let devForeground: string | null = null;

/** Dev server only (`window.__nm.foreground("Code.exe")`): which app is in front, or null for none. */
export function setDevForeground(name: string | null): void {
  devForeground = name;
  State.foregroundKind = name === null ? "none" : "windows";
}

/** The pill a request's mark belongs to: the rule handleHook routes by (the Claude app's session and an untagged request are Claude Code's). */
function pillIdForAgent(nmAgent: unknown): string {
  const raw = typeof nmAgent === "string" ? nmAgent : undefined;
  const agent = validateAgent(raw);
  return isClaudeDesktopTag(raw) || agent === null ? CLAUDE_ID : `agent_${agent}`;
}

/**
 * A hook event, before the island takes it. A permission request whose session may have its app in front waits for the frontmost app's name (stepBackOrNone, at most
 * FOREGROUND_WAIT_MS); when that is the session's own app, the request is stepped back and handleHook declines it. Every other event goes to handleHook at once,
 * one call per event whatever stepBackFor decides.
 */
export function takeHook(island: Island, payload: HookPayload): void {
  void stepBackOrNone({
    kind: State.foregroundKind,
    enabled: focusEnabled(State.settings.focusAware),
    paused: State.paused,
    route: routeHook(payload, State.claudeSessions),
    payload,
    read: IS_TAURI ? () => Bridge.foregroundApp() : () => Promise.resolve(devForeground),
    waitMs: FOREGROUND_WAIT_MS,
    setTimer: (fn, ms) => window.setTimeout(fn, ms),
    clearTimer: (t) => window.clearTimeout(t as number),
    now: Date.now(),
    pillIdOf: pillIdForAgent,
  }).then((mark) => {
    try {
      handleHook(island, payload, mark ?? undefined);
    } catch (err) {
      // Not a step-back: the error goes on as it always did. A step-back the page could not finish is declined, so the terminal takes the request.
      if (mark === null) throw err;
      if (typeof payload.request_id === "string" && payload.request_id !== "") void Bridge.approvalDecline(payload.request_id);
      console.error("[notchmeow] step-back handler failed");
    }
  });
}

/**
 * Exported so that the dev server can feed it fake hook events (main.ts, `window.__nm`); the relay's events come through `takeHook`. A `stepBack` is the mark of a
 * request the session's own app answers (takeHook): it is declined in the PermissionRequest case, and it stays as the session's mark.
 */
export function handleHook(island: Island, payload: HookPayload, stepBack?: FocusMark) {
  island.noteActivity("hook");
  if (State.paused) {
    // Silence here used to cost Claude Code nearly two minutes: the relay waited
    // for a decision from an island that had already decided not to look. Say so,
    // and the terminal takes the question immediately.
    if (payload.request_id) void Bridge.approvalDecline(payload.request_id);
    return;
  }

  // A chat's own Claude Code run asks here too (the same hooks): its card is in that chat, never a pill.
  if (routeHook(payload, State.claudeSessions) === "chat") {
    handleChatHook(island, payload);
    return;
  }

  // Focus awareness: the session's events end its marks, then a step-back's own mark is kept. Before the feed below, so the Sidekick reads the marks as they are now.
  State.endFocusMarks(focusSessionKey(payload), payload.hook_event_name ?? "", payload.tool_name ?? "");
  if (stepBack) State.recordFocusMark(stepBack);
  // The Sidekick's ledger (sub-project F1) is fed here, before anything below can refuse the event: a request that the one card displaces, or that is declined for another
  // agent, is still counted. It never throws and never waits.
  Hub.sk?.hook(payload);
  // Every hook event the island takes starts the tuck-away count again (the place of AppState.touchPill on the Mac).
  island.agentActivity();
  // The Projects registry (sub-project P) is fed here too, for the same reason: a Claude App request answered "ask" below, or one the one card turns away, still counts as waiting. Memory only.
  // A step-back is a "Waiting in <host>" wait (P-tauri's waitIn).
  State.projects.hook(payload, stepBack?.host);

  const name = payload.hook_event_name ?? "";
  const cwd = payload.cwd ?? "";
  const raw = lastPathComponent(cwd);
  const projectName = aliasProjectName(raw || "Session");

  // Route to the right pill. Valid nm_agent → dynamic "agent_<name>" pill.
  // "claude" is reserved; absent or invalid → Claude Code pill unchanged.
  // A session from the Claude desktop app is Claude Code's, whatever its tag: the tag only says that its host is the app (core/openagent.ts).
  const fromClaudeApp = isClaudeDesktopTag(payload.nm_agent);
  const validAgent = fromClaudeApp ? null : validateAgent(payload.nm_agent);
  const agentId = validAgent ? `agent_${validAgent}` : CLAUDE_ID;
  const isExternalAgent = validAgent !== null;
  if (agentId === CLAUDE_ID) State.claudeAppHost = fromClaudeApp;

  const focused = State.focusId === agentId;

  // Subagent kittens (spec §3): a SubagentStart, a tool or permission event with an agent_id, a SubagentStop, the parent's Stop or SessionEnd.
  const kitten = kittenEventOf(payload, performance.now());
  if (kitten) State.kittenEvent(agentId, kitten);

  /** Alerts force the island open; work events only reveal the compact island. */
  const surface = (view: Parameters<Island["alert"]>[0], isAlert: boolean) => {
    if (State.mode === "expanded") {
      if (isAlert) island.setView(view);
    } else if (isAlert) {
      island.alert(view);
    } else if (State.mode === "hidden") {
      island.reveal();
    }
  };

  /** Ensure the agent pill exists (no-op for Claude Code). */
  const ensurePill = () => {
    if (isExternalAgent) {
      State.upsertExternalAgent(agentId, agentPillName(validAgent!), agentColor(validAgent!));
      // The project folder of the agent's session, as the Claude Code pill keeps its own: the Sidekick's drop on an agent's cat opens it. Memory only, never the ledger.
      const pill = State.tasks.find((x) => x.id === agentId);
      if (pill && cwd) pill.sessionCwd = cwd;
    } else {
      upsert(projectName, cwd);
    }
  };

  /**
   * Called where a handler is about to replace `finished` with a newer state: the timer Stop armed would otherwise put the pill back to idle over it.
   * The badge that timer was going to clear goes now.
   */
  const supersedeStop = () => {
    if (stopTimers.cancel(agentId)) State.setPillBadge(agentId, null);
  };

  switch (name) {
    case "SessionStart":
      ensurePill();
      surface("overview", false);
      Sound.play("work");
      break;

    case "UserPromptSubmit": {
      ensurePill();
      supersedeStop();
      State.updateTask(agentId, "thinking");
      // The field is `prompt`; reading `message` meant this step was always blank.
      const asked = payload.prompt ?? payload.message;
      if (asked) State.appendStep(agentId, asked.slice(0, 60));
      surface("overview", false);
      break;
    }

    case "PreToolUse": {
      ensurePill();
      supersedeStop();
      State.updateTask(agentId, toolState(payload.tool_name));
      const tool = payload.tool_name ?? "Tool";
      State.appendStep(agentId, stepLabel(tool, payload.tool_input ?? {}));
      surface("overview", false);
      break;
    }

    case "PostToolUse":
      supersedeStop();
      State.updateTask(agentId, toolState(payload.tool_name));
      break;

    case "PostToolUseFailure":
      supersedeStop();
      State.updateTask(agentId, "working");
      State.appendStep(agentId, "⚠ failed");
      break;

    case "Notification": {
      const message = payload.message ?? "";
      const lower = message.toLowerCase();
      if (lower.includes("rate limit") || lower.includes("limite d")) {
        supersedeStop();
        State.updateTask(agentId, "ratelimit");
        Sound.play("rate");
      } else if (message.endsWith("?")) {
        supersedeStop();
        State.updateTask(agentId, "question");
        State.appendStep(agentId, message);
      }
      break;
    }

    case "Stop":
      State.updateTask(agentId, "finished");
      if (payload.message) State.appendStep(agentId, payload.message.slice(0, 60));
      Sound.play("finish");
      if (focused) surface("finished", true);
      else State.setPillBadge(agentId, "finished");
      stopTimers.arm(agentId, 5200, () => {
        if (isExternalAgent) {
          State.removeTask(agentId);
        } else {
          State.updateTask(agentId, "idle");
          State.setPillBadge(agentId, null);
        }
      });
      break;

    case "StopFailure":
      State.updateTask(agentId, "error");
      Sound.play("error");
      if (focused) surface("error", true);
      else State.setPillBadge(agentId, "error");
      break;

    case "SessionEnd":
      if (isExternalAgent) {
        State.removeTask(agentId);
      } else {
        State.updateTask(agentId, "idle");
        clearSession();
      }
      break;

    case "SubagentStart":
      State.appendStep(agentId, "+ subagent");
      break;

    case "SubagentStop":
      State.appendStep(agentId, "• subagent done");
      break;

    case "PermissionRequest": {
      // Focus awareness: the session's app is in front, so its own prompt is the place to answer. Declined at once (the agent asks there): no card, no sound, nothing opens.
      if (stepBack) {
        if (payload.request_id) void Bridge.approvalDecline(payload.request_id);
        break;
      }
      // External agents do not get an approval card — showing one would look like
      // a Claude Code request. Decline immediately so the agent re-asks in its
      // terminal. Approval support for other agents will come with Codex support.
      // A session from the Claude app is declined the same way: its approvals stay in that app.
      if (isExternalAgent || fromClaudeApp) {
        if (payload.request_id) void Bridge.approvalDecline(payload.request_id);
        break;
      }

      const requestId = payload.request_id ?? "";
      // One card, one request. A second one must never quietly replace the first
      // — that would leave a human staring at request B while request A waits for
      // a decision nobody can give. Hand it straight back to the terminal.
      if (State.pendingApproval && State.pendingApproval.requestId !== requestId) {
        if (requestId) void Bridge.approvalDecline(requestId);
        break;
      }
      upsert(projectName, cwd);
      if (pendingTimeout != null) window.clearTimeout(pendingTimeout);
      const tool = payload.tool_name ?? "Tool";
      const input = payload.tool_input ?? {};
      // The Sidekick's grey line and risk badge (sub-project F1). It only labels: the card, its buttons and the 110 s limit are as they were.
      const why = Hub.sk?.explain(tool, input, cwd) ?? null;
      State.pendingApproval = {
        requestId,
        sessionId: payload.session_id ?? "",
        pillId: agentId,
        tool,
        command: approvalTarget(tool, input),
        ...(typeof payload.agent_id === "string" && payload.agent_id ? { agentId: payload.agent_id } : {}),
        ...(why ? { target: why.target, risk: why.risk, line: why.line } : {}),
      };
      // The relay's short ack window closes in 800 ms; everything below this
      // line is synchronous, so the card really is up by the time it lands.
      if (requestId) void Bridge.approvalAck(requestId);
      State.updateTask(CLAUDE_ID, "approval");
      State.isPinned = true;
      Sound.play("approval");
      if (focused) {
        island.alert("approval");
      } else {
        // Another agent holds the view, so the card would yank it away. The badge
        // is the signal instead — but it has to be on screen for that to mean
        // anything, hence the reveal. We just told the relay a human can act.
        State.setPillBadge(CLAUDE_ID, "approval");
        island.reveal();
      }
      // A high risk gives the cat the surprised emote, once (no new emote). If the desktop cat is out it flies to the notch for this request with that very emote already.
      if (why?.risk === "high" && !State.desktopNotchEmpty) island.emote("surprised");
      // NotchMeow answers within 108 s or not at all; after that the terminal has
      // taken over and the card would be lying.
      pendingTimeout = window.setTimeout(() => {
        pendingTimeout = null;
        if (!State.pendingApproval) return;
        State.subagentApprovalOver(State.pendingApproval);
        State.pendingApproval = null;
        State.isPinned = false;
        island.dropPin();
        State.updateTask(CLAUDE_ID, "working");
        State.setPillBadge(CLAUDE_ID, null);
        if (State.view === "approval") island.setView(State.defaultView());
        resurfaceChatApproval(island);
        State.notify();
      }, 110_000);
      break;
    }

    default:
      break;
  }
  State.noteEvent(agentId);
  State.notify();
}
