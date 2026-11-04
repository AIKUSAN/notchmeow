import test from "node:test";
import assert from "node:assert/strict";
import { kittenView, kittenStep } from "../../src/cat/kittens.ts";
import { kittenEventOf } from "../../src/island/subagents.ts";

// The hook events that mean something to a pill's kittens (spec §3), and what the kitten list does with them, end to end.
const ev = (p, t = 1000) => kittenEventOf(p, t);
const ids = (list) => list.map((k) => k.id);

test("SubagentStart is a kitten, with its type and its session; a tool, a permission request and SubagentStop carry the subagent's id", () => {
  assert.deepEqual(ev({ hook_event_name: "SubagentStart", agent_id: "a1", agent_type: "Explore", session_id: "s1" }), { type: "start", id: "a1", agentType: "Explore", session: "s1", t: 1000 });
  assert.deepEqual(ev({ hook_event_name: "SubagentStart", agent_id: "a1" }), { type: "start", id: "a1", t: 1000 });
  for (const name of ["PreToolUse", "PostToolUse"]) assert.deepEqual(ev({ hook_event_name: name, agent_id: "a1", tool_name: "Grep" }), { type: "tool", id: "a1", tool: "Grep", t: 1000 }, name);
  assert.deepEqual(ev({ hook_event_name: "PermissionRequest", agent_id: "a1", tool_name: "Bash" }), { type: "permission", id: "a1", t: 1000 });
  assert.deepEqual(ev({ hook_event_name: "SubagentStop", agent_id: "a1", agent_type: "Explore" }), { type: "stop", id: "a1", t: 1000 });
});

test("a tool or permission event with no agent_id is the parent's own: no kitten event (a Claude Code that sends none still gets kittens at start and stop)", () => {
  for (const name of ["PreToolUse", "PostToolUse", "PermissionRequest", "SubagentStart", "SubagentStop"]) {
    assert.equal(ev({ hook_event_name: name, tool_name: "Bash" }), null, name);
    assert.equal(ev({ hook_event_name: name, agent_id: "", tool_name: "Bash" }), null, `${name} with an empty id`);
    assert.equal(ev({ hook_event_name: name, agent_id: 7, tool_name: "Bash" }), null, `${name} with a number`);
    assert.equal(ev({ hook_event_name: name, agent_id: "x".repeat(129) }), null, `${name} with a very long id`);
  }
});

test("the parent's Stop, StopFailure and SessionEnd end the kittens of their session; the same events inside a subagent do not", () => {
  assert.deepEqual(ev({ hook_event_name: "Stop", session_id: "s1" }), { type: "end", session: "s1", t: 1000 });
  assert.deepEqual(ev({ hook_event_name: "StopFailure", session_id: "s1" }), { type: "end", session: "s1", t: 1000 }, "a turn that ended in an error ends them too");
  assert.deepEqual(ev({ hook_event_name: "SessionEnd", session_id: "s1" }), { type: "end", session: "s1", t: 1000 });
  assert.deepEqual(ev({ hook_event_name: "SessionEnd" }), { type: "end", t: 1000 }, "no session: every kitten");
  assert.equal(ev({ hook_event_name: "Stop", session_id: "s1", agent_id: "a1" }), null, "a subagent's own Stop is not the parent's");
});

test("every other hook event, and every payload that is not an object, is no kitten event; a time that is not a time is none either", () => {
  for (const name of ["SessionStart", "UserPromptSubmit", "PostToolUseFailure", "Notification", "StopFailure", "BeforeTool", "", undefined, 7]) assert.equal(ev({ hook_event_name: name, agent_id: "a1" }), null, String(name));
  for (const p of [null, undefined, 7, "x", [], [{ hook_event_name: "Stop" }]]) assert.equal(ev(p), null, String(JSON.stringify(p)));
  for (const t of [NaN, Infinity, "1", null, undefined]) assert.equal(kittenEventOf({ hook_event_name: "SubagentStop", agent_id: "a1" }, t), null, String(t));
});

test("a whole subagent's life through the reducer: start, search, ask, answer, work, stop, gone; and the fallback with no agent_id on the tool events", () => {
  const feed = (list, p, t) => { const e = kittenEventOf(p, t); return e ? kittenStep(list, e) : list; };
  let l = [];
  l = feed(l, { hook_event_name: "SubagentStart", agent_id: "a1", agent_type: "Explore", session_id: "s1" }, 1);
  l = feed(l, { hook_event_name: "PreToolUse", agent_id: "a1", tool_name: "Grep" }, 2);
  assert.equal(l[0].state, "searching");
  l = feed(l, { hook_event_name: "PermissionRequest", agent_id: "a1", tool_name: "Bash" }, 3);
  assert.equal(l[0].state, "approval");
  l = kittenStep(l, { type: "resolved", id: "a1", t: 4 });
  assert.equal(l[0].state, "working");
  l = feed(l, { hook_event_name: "PostToolUse", agent_id: "a1", tool_name: "Bash" }, 5);
  l = feed(l, { hook_event_name: "SubagentStop", agent_id: "a1" }, 6);
  assert.equal(l[0].state, "leaving");
  assert.deepEqual(ids(kittenView(l, 6 + 599)), ["a1"]);
  assert.deepEqual(ids(kittenView(l, 6 + 600)), []);
  // The fallback: tool events carry no agent_id, so the kitten stays in the working pose from its start to its stop.
  let f = feed([], { hook_event_name: "SubagentStart", agent_id: "b1", session_id: "s1" }, 1);
  f = feed(f, { hook_event_name: "PreToolUse", tool_name: "Grep" }, 2);
  assert.equal(f[0].state, "working");
  f = feed(f, { hook_event_name: "Stop", session_id: "s9" }, 3);
  assert.equal(f.length, 1, "a Stop of another session leaves this session's kitten alone");
  f = feed(f, { hook_event_name: "SessionEnd" }, 4);
  assert.deepEqual(f, []);
});
