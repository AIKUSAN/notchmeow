import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { createRequire } from "node:module";
import {
  MARK_LIFETIME_MS, MARKS_MAX, ENDING_EVENTS, focusEnabled, focusSessionKey, focusHost, matchForeground, raceForeground, noteText,
  showsDot, showsNoteOverSecondLine, lineWaits, recordMark, endMarks, liveMarks, markForPill, markForSession, lapseMs,
  FOREGROUND_WAIT_MS, stepBackFor, stepBackOrNone,
} from "../../src/core/focusaware.ts";
import { stepVerb } from "../../src/core/steps.ts";
import { APP_WAIT_MS, APP_WAIT_LABEL } from "../../src/projects/core.ts";

const require = createRequire(import.meta.url);
const core = require("../../../shared/sidekick-core.js");
const swift = fs.readFileSync(new URL("../../../NotchBuddy/Sources/App/FocusAware.swift", import.meta.url), "utf8");
const projectsSwift = fs.readFileSync(new URL("../../../NotchBuddy/Sources/App/ProjectsRules.swift", import.meta.url), "utf8");

const mark = { sessionId: "S1", pillId: "integration_claude", host: "VS Code", kind: "permission", words: "Edits", at: 1_000_000 };
const clone = (v) => structuredClone(v);

test("the setting reads on unless it is false", () => {
  assert.deepEqual([undefined, true, "no", 0, null].map((v) => focusEnabled(v)), [true, true, true, true, true]);
  assert.equal(focusEnabled(false), false);
});

test("the session key is the Sidekick ledger's", () => {
  const payloads = [
    { session_id: "S1" },
    { session_id: "", conversation_id: "C" },
    {},
    { session_id: 42 },
    { session_id: "x".repeat(130) },
    { session_id: "\u{1F431}".repeat(130) },
  ];
  for (const p of payloads) {
    const withEvent = { ...p, hook_event_name: "PermissionRequest" };
    assert.equal(focusSessionKey(withEvent), core.eventFrom(withEvent, 1).sessionId);
  }
});

test("Windows hosts", () => {
  const names = (h) => h && h.apps.map((a) => a.name);
  assert.deepEqual(focusHost({ nm_agent: "claude-desktop", term_program: "vscode" }, "windows").apps, [{ name: "Claude.exe", words: "Claude App" }]);
  assert.deepEqual(names(focusHost({ term_program: "VSCode", wt_session: "x" }, "windows")), ["Code.exe", "Code - Insiders.exe", "VSCodium.exe", "Cursor.exe"]);
  assert.deepEqual(focusHost({ term_program: "", wt_session: "abc" }, "windows").apps, [{ name: "WindowsTerminal.exe", words: "Windows Terminal" }]);
  assert.equal(focusHost({ wt_session: "" }, "windows"), null);
  assert.deepEqual(focusHost({ nm_agent: "gemini", wt_session: "abc" }, "windows").apps, [{ name: "WindowsTerminal.exe", words: "Windows Terminal" }]);
  assert.equal(focusHost({ term_program: "vscode", wt_session: "abc" }, "none"), null);
  assert.equal(focusHost({ nm_agent: "claude-desktop" }, "none"), null);
});

test("X11 hosts", () => {
  const names = (h) => h && h.apps.map((a) => a.name);
  assert.deepEqual(names(focusHost({ term_program: "vscode" }, "x11")), ["Code", "Code - Insiders", "VSCodium", "Cursor"]);
  assert.deepEqual(focusHost({ term_program: "WezTerm" }, "x11").apps, [{ name: "org.wezfurlong.wezterm", words: "WezTerm" }]);
  assert.deepEqual(focusHost({ term_program: "ghostty" }, "x11").apps, [{ name: "com.mitchellh.ghostty", words: "Ghostty" }]);
  assert.equal(focusHost({ nm_agent: "claude-desktop" }, "x11"), null);
  assert.equal(focusHost({ term_program: "xterm" }, "x11"), null);
});

test("no row names the shell or the app itself", () => {
  const payloads = [{ nm_agent: "claude-desktop" }, { term_program: "vscode" }, { term_program: "kitty" }, { term_program: "wezterm" },
    { term_program: "alacritty" }, { term_program: "ghostty" }, { wt_session: "x" }];
  const all = [];
  for (const kind of ["windows", "x11"]) for (const p of payloads) for (const a of focusHost(p, kind)?.apps ?? []) all.push(a.name.toLowerCase());
  assert.ok(all.length > 0);
  for (const bad of ["explorer.exe", "notchmeow.exe", "notchmeow"]) assert.ok(!all.includes(bad), bad);
});

test("the match gives the app's words", () => {
  const vscode = focusHost({ term_program: "vscode" }, "windows");
  assert.equal(matchForeground(vscode, "code.exe"), "VS Code");
  assert.equal(matchForeground(vscode, "CURSOR.EXE"), "Cursor");
  assert.equal(matchForeground(vscode, "WindowsTerminal.exe"), null);
  assert.equal(matchForeground(vscode, null), null);
  assert.equal(matchForeground(vscode, ""), null);
});

test("the race", async () => {
  const timers = [];
  const setTimer = (fn, ms) => { const t = { fn, ms, cleared: false }; timers.push(t); return t; };
  const clearTimer = (t) => { t.cleared = true; };
  assert.equal(await raceForeground(() => Promise.resolve("Code.exe"), 300, setTimer, clearTimer), "Code.exe");
  assert.equal(timers[0].cleared, true);
  assert.equal(timers[0].ms, 300);

  const late = [];
  const never = raceForeground(() => new Promise(() => {}), 300, (fn, ms) => { late.push(fn); return fn; }, () => {});
  late[0]();
  assert.equal(await never, null);

  const rejected = [];
  const rej = raceForeground(() => Promise.reject(new Error("no")), 300, (fn, ms) => { const t = { fn, cleared: false }; rejected.push(t); return t; }, (t) => { t.cleared = true; });
  assert.equal(await rej, null);
  assert.equal(rejected[0].cleared, true);

  const thrown = [];
  let syncReads = 0;
  const sync = raceForeground(() => { syncReads++; throw new Error("no"); }, 300, (fn) => { const t = { fn, cleared: false }; thrown.push(t); return t; }, (t) => { t.cleared = true; });
  assert.equal(await sync, null, "a read that throws synchronously is no name");
  assert.equal(syncReads, 1);
  assert.equal(thrown[0].cleared, true);
});

/** The gates' inputs for stepBackFor: a VS Code permission request on Windows, read as Code.exe, with the timers and reads counted. */
function stepInput(over = {}) {
  const calls = { read: 0 };
  const timers = [];
  const pillCalls = [];
  const input = {
    kind: "windows", enabled: true, paused: false, route: "other",
    payload: { hook_event_name: "PermissionRequest", session_id: "S1", tool_name: "Bash", term_program: "vscode" },
    read: () => { calls.read++; return Promise.resolve("Code.exe"); },
    waitMs: FOREGROUND_WAIT_MS,
    setTimer: (fn, ms) => { const t = { fn, ms, cleared: false }; timers.push(t); return t; },
    clearTimer: (t) => { t.cleared = true; },
    now: 42,
    pillIdOf: (agent) => { pillCalls.push(agent); return agent === "gemini" ? "agent_gemini" : "integration_claude"; },
    ...over,
  };
  return { input, calls, timers, pillCalls };
}

test("stepBackFor: a permission request from the session's own app is a mark with the app's words, the pill and the step's verb", async () => {
  const { input, calls } = stepInput();
  assert.deepEqual(await stepBackFor(input), {
    sessionId: "S1", pillId: "integration_claude", host: "VS Code", kind: "permission", words: stepVerb("Bash"), at: 42,
  });
  assert.equal(calls.read, 1);
});

test("stepBackFor: another app in front is no mark", async () => {
  const { input, calls } = stepInput({ read: () => { calls.read++; return Promise.resolve("chrome.exe"); } });
  assert.equal(await stepBackFor(input), null);
  assert.equal(calls.read, 1);
});

test("stepBackFor: a read that rejects is no mark, and the read was asked", async () => {
  const { input, calls } = stepInput({ read: () => { calls.read++; return Promise.reject(new Error("no")); } });
  assert.equal(await stepBackFor(input), null);
  assert.equal(calls.read, 1);
});

test("stepBackFor: a read that never answers is no mark once the timer fires", async () => {
  const { input, calls, timers } = stepInput({ read: () => { calls.read++; return new Promise(() => {}); } });
  const pending = stepBackFor(input);
  assert.equal(timers.length, 1, "the wait is set when the request comes");
  assert.equal(timers[0].ms, 300);
  timers[0].fn();
  assert.equal(await pending, null);
  assert.equal(calls.read, 1);
});

test("stepBackFor: the gates stop the read before it starts", async () => {
  const gated = [
    ["kind none", { kind: "none" }],
    ["the switch off", { enabled: false }],
    ["paused", { paused: true }],
    ["a Notification", { payload: { hook_event_name: "Notification", session_id: "S1", term_program: "vscode" } }],
    ["no host on this OS", { payload: { hook_event_name: "PermissionRequest", session_id: "S1" } }],
  ];
  for (const [why, over] of gated) {
    const { input, calls } = stepInput(over);
    assert.equal(await stepBackFor(input), null, why);
    assert.equal(calls.read, 0, `${why}: the app is not asked`);
  }
});

test("stepBackFor: a chat's own run is never stepped back, even when its terminal is in front", async () => {
  const { input, calls } = stepInput({ route: "chat", payload: { hook_event_name: "PermissionRequest", session_id: "S1", wt_session: "x" }, read: () => { calls.read++; return Promise.resolve("WindowsTerminal.exe"); } });
  assert.equal(await stepBackFor(input), null);
  assert.equal(calls.read, 0);
});

test("stepBackFor: an AskUserQuestion is a question with no words", async () => {
  const { input } = stepInput({ payload: { hook_event_name: "PermissionRequest", session_id: "S1", tool_name: "AskUserQuestion", term_program: "vscode" } });
  const mark = await stepBackFor(input);
  assert.equal(mark.kind, "question");
  assert.equal(mark.words, null);
  assert.equal(mark.host, "VS Code");
});

test("stepBackFor: the pill comes from the injected rule, with the request's agent tag", async () => {
  const { input, pillCalls } = stepInput({ payload: { hook_event_name: "PermissionRequest", session_id: "S1", tool_name: "Edit", nm_agent: "gemini", term_program: "vscode" } });
  const mark = await stepBackFor(input);
  assert.equal(mark.pillId, "agent_gemini");
  assert.deepEqual(pillCalls, ["gemini"]);
  assert.equal(mark.words, stepVerb("Edit"));
});

test("stepBackFor: a read that throws synchronously is no mark", async () => {
  const { input, calls } = stepInput({ read: () => { calls.read++; throw new Error("no"); } });
  assert.equal(await stepBackFor(input), null);
  assert.equal(calls.read, 1);
});

test("stepBackOrNone: a rejection or a synchronous throw is no mark, so the event still reaches handleHook with none", async () => {
  const ok = stepInput();
  assert.deepEqual((await stepBackOrNone(ok.input)).host, "VS Code", "a match is the mark");
  const rejected = stepInput({ setTimer: () => { throw new Error("no timer"); } });
  assert.equal(await stepBackOrNone(rejected.input), null, "a setTimer that throws inside the race is a rejection, and it is no mark");
  assert.equal(rejected.calls.read, 0, "the app was not asked");
  const sync = stepInput();
  Object.defineProperty(sync.input, "kind", { get() { throw new Error("getter fails"); } });
  assert.equal(await stepBackOrNone(sync.input), null, "a throw before the race is no mark too");
});

test("the wait is pinned against the relay's ack window: 300 ms, and at most 400 ms under pipe.rs's 800 ms ACK_TIMEOUT", () => {
  assert.equal(FOREGROUND_WAIT_MS, 300);
  const pipe = fs.readFileSync(new URL("../../src-tauri/src/pipe.rs", import.meta.url), "utf8");
  const ack = /const ACK_TIMEOUT: Duration = Duration::from_millis\((\d+)\);/.exec(pipe);
  assert.ok(ack, "ACK_TIMEOUT is a millisecond literal in pipe.rs");
  assert.equal(Number(ack[1]), 800);
  assert.ok(FOREGROUND_WAIT_MS <= 400, "the wait never eats the ack budget");
});

test("words, dot and cat 2's line", () => {
  assert.equal(noteText("VS Code", "Runs"), "Waiting in VS Code: Runs");
  assert.equal(noteText("Windows Terminal", null), "Waiting in Windows Terminal");
  assert.equal(noteText("  ", "Edits"), "Waiting in Claude App: Edits");
  assert.equal(stepVerb("PowerShell"), "Runs");
  assert.equal(stepVerb("Edit"), "Edits");
  assert.equal(stepVerb("AskUserQuestion"), null);
  assert.equal(stepVerb("constructor"), null);
  const bools = [true, false];
  const dots = [];
  for (const a of bools) for (const b of bools) for (const c of bools) if (showsDot(a, b, c)) dots.push([a, b, c]);
  const notes = [];
  for (const a of bools) for (const b of bools) if (showsNoteOverSecondLine(a, b)) notes.push([a, b]);
  assert.deepEqual(dots, [[true, false, false]]);
  assert.deepEqual(notes, [[true, false]]);
});

test("lineWaits: cat 2's second line waits exactly for approval and question; an unknown or missing state does not", () => {
  for (const st of ["approval", "question"]) assert.equal(lineWaits(st), true, st);
  for (const st of ["working", "idle", "thinking", "searching", "finished", "error", "ratelimit", "sleeping", undefined, null]) assert.equal(lineWaits(st), false, String(st));
  assert.equal(showsNoteOverSecondLine(true, lineWaits("working")), true, "a working line does not hold the note back");
  assert.equal(showsNoteOverSecondLine(true, lineWaits("approval")), false, "an approval line stays");
  assert.equal(showsNoteOverSecondLine(true, lineWaits("question")), false, "a question line stays");
});

test("marks", () => {
  const m = clone(mark);
  assert.equal(liveMarks([m], m.at + 599_999).length, 1);
  assert.equal(liveMarks([m], m.at + 600_000).length, 0);
  assert.equal(liveMarks([m], m.at - 5000).length, 1);
  assert.equal(liveMarks([m], m.at - 600_000).length, 0);

  const replaced = recordMark([m], { ...m, words: "Runs", at: m.at + 1000 });
  assert.equal(replaced.length, 1);
  assert.equal(replaced[0].words, "Runs");

  assert.equal(endMarks([m], "S1", "PreToolUse", "AskUserQuestion").length, 1);
  assert.equal(endMarks([m], "S1", "Notification", "Bash").length, 1);
  assert.equal(endMarks([m], "S2", "Stop", "Bash").length, 1);
  for (const ev of ENDING_EVENTS) assert.equal(endMarks([m], "S1", ev, "Bash").length, 0, ev);

  let list = [];
  for (let i = 0; i < 70; i++) list = recordMark(list, { ...m, sessionId: `S${i}`, at: 1_000_000 + i * 1000 });
  assert.equal(list.length, MARKS_MAX);
  assert.equal(Math.min(...list.map((x) => x.at)), 1_000_000 + 6 * 1000);

  const snapshot = clone([m]);
  recordMark([m], { ...m, words: "Runs" });
  endMarks([m], "S1", "Stop", "Bash");
  assert.deepEqual([m], snapshot);
  const big = clone(list);
  recordMark(list, { ...m, sessionId: "Z", at: 1_000_000 + 80_000 });
  endMarks(list, "S10", "Stop", "Bash");
  assert.deepEqual(list, big);

  const other = { ...m, pillId: "agent_cursor", host: "Cursor", at: 1_100_000 };
  const both = recordMark([m], other);
  assert.equal(markForSession(both, "S1", 1_200_000).pillId, "agent_cursor");
  assert.equal(markForPill(both, "integration_claude", 1_200_000).sessionId, "S1");
  assert.equal(markForSession(both, "S1", 1_700_000), null);

  assert.equal(lapseMs(1_000_000, 1_060_000, 5_000), 545_000);
});

test("the shared rules match the Swift", () => {
  assert.equal(MARK_LIFETIME_MS, 600 * 1000);
  assert.equal(MARK_LIFETIME_MS, APP_WAIT_MS);
  assert.match(swift, /static let markLifetime: Double = 600/);
  assert.match(swift, /static let marksMax = 64/);
  const literal = swift.match(/static let endingEvents: \[String\] = \[([^\]]*)\]/);
  assert.ok(literal, "endingEvents literal");
  assert.deepEqual([...literal[1].matchAll(/"([A-Za-z]+)"/g)].map((x) => x[1]), [...ENDING_EVENTS]);
  assert.ok(swift.includes('!(event == "PreToolUse" && tool == "AskUserQuestion")'));
  assert.match(projectsSwift, /static let appWaitLabel = "Waiting in Claude App"/);
  assert.equal(APP_WAIT_LABEL, "Waiting in Claude App");
});
