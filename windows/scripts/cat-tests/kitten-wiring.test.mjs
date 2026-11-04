import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { SLEEP_AFTER_MS } from "../../src/cat/base.ts";
import { KITTEN_LEAVE_MS } from "../../src/cat/kittens.ts";
import { State } from "../../src/core/state.ts";
import { SleepClock } from "../../src/island/sleep.ts";
import { kittenEventOf } from "../../src/island/subagents.ts";

// The kittens in State, the hook handlers that feed them, the sweep that comes with the cat falling asleep and the approval a subagent asked for. hooks.ts needs a browser, so the handlers are pinned by source.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const MIN = 60_000;
const task = (id) => ({ id, name: id, color: "#8AB4F8", state: "idle", stepIndex: 0, steps: [], source: "agent", isIntegration: false });
const reset = () => { State.tasks = [task("integration_claude"), task("agent_gemini")]; State.kittens = {}; State.pendingApproval = null; };
/** What handleHook does with a hook event's kitten part: map it and give it to the pill. */
const feed = (pill, payload, t) => { const e = kittenEventOf(payload, t); if (e) State.kittenEvent(pill, e); };
const ids = (pill, now) => State.kittenView(pill, now).map((k) => k.id);

test("a subagent's life in State: start, tool, ask, answer, stop, gone; each pill has its own list, and nothing is ever stored", () => {
  reset();
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "a1", agent_type: "Explore", session_id: "s1" }, 1000);
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "a2", session_id: "s1" }, 1001);
  feed("integration_claude", { hook_event_name: "PreToolUse", agent_id: "a1", tool_name: "Grep" }, 1002);
  assert.deepEqual(State.kittenView("integration_claude", 1003).map((k) => [k.id, k.state]), [["a2", "working"], ["a1", "searching"]]);
  feed("integration_claude", { hook_event_name: "PermissionRequest", agent_id: "a1", tool_name: "Bash" }, 1004);
  assert.deepEqual(ids("integration_claude", 1005), ["a1", "a2"], "a kitten waiting on an approval first");
  State.subagentApprovalOver({ requestId: "r", sessionId: "s1", tool: "Bash", command: "ls", agentId: "a1" }, 1006);
  assert.equal(State.kittenView("integration_claude", 1007).find((k) => k.id === "a1").state, "working", "answered: back to working");
  feed("integration_claude", { hook_event_name: "SubagentStop", agent_id: "a1" }, 2000);
  assert.deepEqual(ids("integration_claude", 2000 + KITTEN_LEAVE_MS - 1), ["a2", "a1"], "a1 is leaving: still drawn");
  assert.deepEqual(ids("integration_claude", 2000 + KITTEN_LEAVE_MS), ["a2"], "and gone from 600 ms on, with no event and no timer");
  assert.deepEqual(State.kittenView("agent_gemini", 2000), [], "another pill has none");
  assert.equal(JSON.stringify(State.settings).includes("a2"), false, "kittens are never in the settings");
  assert.equal(JSON.stringify(State.settings.cat).includes("kitten"), false);
});

test("an event for a pill that is not there is ignored; a late event brings nothing back; the parent's Stop and a removed pill take their kittens", () => {
  reset();
  feed("agent_unknown", { hook_event_name: "SubagentStart", agent_id: "x" }, 1);
  assert.deepEqual(State.kittens, {});
  feed("integration_claude", { hook_event_name: "PreToolUse", agent_id: "ghost", tool_name: "Bash" }, 2);
  assert.deepEqual(State.kittens, {}, "a tool event for an id that never started creates nothing");
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "a1", session_id: "s1" }, 3);
  feed("integration_claude", { hook_event_name: "Stop", session_id: "s1" }, 4);
  assert.deepEqual(State.kittens, {}, "the parent stopped: no kittens left, and no empty list is kept");
  feed("agent_gemini", { hook_event_name: "SubagentStart", agent_id: "g1" }, 5);
  assert.equal(State.kittenView("agent_gemini", 6).length, 1);
  State.removeTask("agent_gemini");
  assert.deepEqual(State.kittens, {}, "a pill that goes takes its kittens");
});

test("a subagent's own approval: the request names its agent_id, and the kitten waits until the approval is answered or times out; a parent's approval touches no kitten", () => {
  reset();
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "a1" }, 1);
  feed("integration_claude", { hook_event_name: "PermissionRequest", agent_id: "a1" }, 2);
  assert.equal(State.kittenView("integration_claude", 3)[0].state, "approval");
  State.subagentApprovalOver({ requestId: "r", sessionId: "s", tool: "Bash", command: "ls" }, 4);
  assert.equal(State.kittenView("integration_claude", 5)[0].state, "approval", "the parent's own request (no agentId) leaves it waiting");
  State.subagentApprovalOver(null, 5);
  State.subagentApprovalOver({ requestId: "r", sessionId: "s", tool: "Bash", command: "ls", agentId: "a1" }, 6);
  assert.equal(State.kittenView("integration_claude", 7)[0].state, "working");
  const hooks = source("island/hooks.ts"), island = source("island/island.ts");
  assert.match(hooks, /\.\.\.\(typeof payload\.agent_id === "string" && payload\.agent_id \? \{ agentId: payload\.agent_id \} : \{\}\),/);
  assert.match(hooks, /State\.subagentApprovalOver\(State\.pendingApproval\);\s*State\.pendingApproval = null;/, "the 108 s timeout");
  assert.match(island, /State\.subagentApprovalOver\(req\);\s*State\.pendingApproval = null;/, "Allow and Deny");
});

test("the hook handlers feed the kittens before anything else changes, with the clock the lists use, and the relay's agent_id reaches them", () => {
  const hooks = source("island/hooks.ts");
  assert.match(hooks, /const focused = State\.focusId === agentId;\s*\/\/ Subagent kittens[^\n]*\n\s*const kitten = kittenEventOf\(payload, performance\.now\(\)\);\s*if \(kitten\) State\.kittenEvent\(agentId, kitten\);/);
  assert.match(hooks, /agent_id\?: string;\s*agent_type\?: string;/);
  assert.match(hooks, /case "SubagentStart":\s*State\.appendStep\(agentId, "\+ subagent"\);/, "the ticker's lines are as they were");
  assert.match(hooks, /case "SubagentStop":\s*State\.appendStep\(agentId, "• subagent done"\);/);
  assert.match(fs.readFileSync(new URL("../../hook/src/main.rs", import.meta.url), "utf8"), /DROPPED_FIELDS: &\[&str\] = &\["tool_response", "transcript_path", "agent_transcript_path", "last_assistant_message", "prompt_response"\];/, "the relay drops the big and the private fields, and the agent_id and agent_type are not among them");
});

/** A clock and a timer queue turned by hand, and a cat that records the sweeps and the falls asleep. `w.blocked` is an approval waiting for the user. */
function world(state = "idle") {
  const w = { t: 0, state, blocked: false, timers: new Map(), id: 1, sweeps: 0, falls: 0 };
  const env = {
    now: () => w.t, state: () => w.state, blocked: () => w.blocked,
    set: (fn, ms) => { const id = w.id++; w.timers.set(id, { fn, at: w.t + ms }); return id; }, clear: (id) => { w.timers.delete(id); },
    fall: () => { w.falls++; }, wake: () => {}, sweep: () => { w.sweeps++; State.sweepKittens(w.t); },
  };
  w.advance = (ms) => {
    const end = w.t + ms;
    for (;;) {
      const due = [...w.timers.entries()].filter(([, x]) => x.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      w.t = due[1].at; w.timers.delete(due[0]); due[1].fn();
    }
    w.t = end;
  };
  return { w, clock: new SleepClock(env) };
}

test("falling asleep sweeps the kittens whose stop never came; an event starts the ten minutes again; an approval that waits blocks both; there is no other timer", () => {
  reset();
  const { w, clock } = world("idle");
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "lost" }, 0);
  w.advance(SLEEP_AFTER_MS - 1);
  assert.equal(w.sweeps, 0);
  assert.equal(State.kittenView("integration_claude", w.t).length, 1);
  w.advance(1);
  assert.deepEqual([w.falls, w.sweeps], [1, 1], "ten quiet minutes: the cat falls asleep, and the sweep comes with it");
  assert.deepEqual(State.kittens, {}, "the lost kitten is gone");
  assert.equal(w.timers.size, 0, "and nothing is armed again until the next event");
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "a" }, w.t);
  clock.event("hook");
  w.advance(5 * MIN);
  feed("integration_claude", { hook_event_name: "PreToolUse", agent_id: "a", tool_name: "Bash" }, w.t);
  clock.event("hook");
  w.advance(9 * MIN);
  assert.deepEqual([w.falls, w.sweeps], [1, 1], "each event starts the ten minutes again: nothing fell asleep, nothing was swept");
  w.blocked = true;
  w.advance(MIN);
  assert.deepEqual([w.falls, w.sweeps], [1, 1], "an approval is waiting: the cat does not sleep through it, so nothing is swept either");
  assert.equal(State.kittenView("integration_claude", w.t).length, 1);
  w.blocked = false;
  clock.event("hook");
  w.advance(SLEEP_AFTER_MS);
  assert.deepEqual([w.falls, w.sweeps], [2, 2]);
  assert.match(source("island/island.ts"), /fall: \(\) => State\.fallAsleep\(\),\s*sweep: \(\) => State\.sweepKittens\(\),/);
});

test("a working cat's timer firing sweeps nothing: a subagent in a long, silent step is alive, and its kitten stays", () => {
  reset();
  const { w, clock } = world("working");
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "slow" }, 0);
  w.advance(SLEEP_AFTER_MS + 5 * MIN);
  assert.deepEqual([w.falls, w.sweeps], [0, 0], "a working cat neither falls asleep nor sweeps");
  assert.equal(State.kittenView("integration_claude", w.t).length, 1, "the kitten of the long step is still there");
  assert.equal(w.timers.size, 0, "and nothing is armed again until the next event");
  w.state = "idle";                                    // the turn is over; the stop of the subagent never came
  clock.event("hook");
  w.advance(SLEEP_AFTER_MS);
  assert.deepEqual([w.falls, w.sweeps], [1, 1], "once the cat is idle for ten quiet minutes it falls asleep, and the lost kitten goes");
  assert.deepEqual(State.kittens, {});
});

test("a kitten that was busy lately survives the sweep; one that was quiet for ten minutes does not", () => {
  reset();
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "quiet" }, 0);
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "busy" }, 1);
  feed("integration_claude", { hook_event_name: "PostToolUse", agent_id: "busy", tool_name: "Bash" }, SLEEP_AFTER_MS - 10);
  State.sweepKittens(SLEEP_AFTER_MS + 5);
  assert.deepEqual(ids("integration_claude", SLEEP_AFTER_MS + 5), ["busy"]);
});
