import test from "node:test";
import assert from "node:assert/strict";
import { HOLD_MS, NOTE_GAP_MS, cleanSidekickSettings } from "../../src/sidekick/core.ts";
import { Notes } from "../../src/sidekick/notes.ts";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { QUIET_VIEWS, worldOf } from "../../src/sidekick/world.ts";
import { sidekickHeight } from "../../src/core/layout.ts";
import { source } from "./util.mjs";

const MIN = 60_000;
const T0 = 5_000_000;

/** A world the test sets by hand, and every call the Notes make on it written down. */
function world(settings = {}) {
  const w = {
    t: T0, settings: cleanSidekickSettings(settings), away: false, ratelimit: false, card: null, ownCard: false, typing: false, onScreen: null, nudged: new Set(),
    presented: [], shown: [], dropped: [], folded: [], dismissed: [], updated: [], valid: true,
  };
  const notes = new Notes({
    now: () => w.t, settings: () => w.settings,
    world: { ratelimit: () => w.ratelimit, card: () => w.card, ownCard: () => w.ownCard, typing: () => w.typing, away: () => w.away, onScreen: (id) => (w.onScreen === null ? w.presented.at(-1)?.id === id : w.onScreen === id) },
    nudged: (key) => w.nudged.has(key), valid: () => w.valid !== false, updated: (n) => w.updated.push(n),
    present: (n) => w.presented.push(n), shown: (n) => w.shown.push(n), dropped: (n) => w.dropped.push(n), folded: (n) => w.folded.push(n),
    dismissed: (kind) => { w.dismissed.push(kind); w.settings = cleanSidekickSettings({ ...w.settings, dismissals: { ...w.settings.dismissals, [kind]: Math.min(2, w.settings.dismissals[kind] + 1) } }); },
  });
  return { w, notes };
}
const recap = (awaySince = T0 - 10 * MIN) => ({ kind: "recap", agentId: "", key: "", lines: ["While you were away, Claude Code ran 3 steps and finished."], facts: [{ agent: "Claude Code", steps: 3 }], awaySince });
const nudge = (kind = "stuck.loop", key = "integration_claude|S1") => ({ kind, agentId: "integration_claude", key, lines: ["Claude Code has run the same step 4 times."], facts: [{ agent: "Claude Code" }], awaySince: null });

test("a note on a quiet screen shows at once, through the island's peek, and a nudge marks its session", () => {
  const { w, notes } = world();
  assert.equal(notes.offer(nudge()), "ok");
  assert.equal(w.presented.length, 1);
  assert.equal(w.presented[0].kind, "stuck.loop");
  assert.equal(w.shown.length, 1);
  assert.equal(notes.current.id, w.presented[0].id);
  assert.deepEqual(notes.waiting, []);
});

test("a refusal that can pass keeps the note, and it shows when the gate opens; a nudge waits 30 s and a recap 2 minutes, then both go without a word", () => {
  for (const [reason, set] of [["card", (w) => { w.card = "approval"; }], ["typing", (w) => { w.typing = true; }]]) {
    const { w, notes } = world();
    set(w);
    assert.equal(notes.offer(nudge()), reason);
    assert.equal(w.presented.length, 0);
    assert.equal(notes.waiting.length, 1, `${reason}: kept`);
    w.card = null; w.typing = false; w.away = false; w.t += 10_000;
    notes.retry();
    assert.equal(w.presented.length, 1, `${reason}: shown when the gate opened`);
    assert.equal(notes.waiting.length, 0);
  }
  // Away (spec: a nudge that fell due while the user was away is dropped, not saved for later; the recap covers it). A nudge is never kept while away; a recap is.
  const away = world();
  away.w.away = true;
  assert.equal(away.notes.offer(nudge()), "away");
  assert.equal(away.notes.waiting.length, 0, "away: a nudge is dropped at once");
  away.w.away = false;
  away.notes.retry();
  assert.equal(away.w.presented.length, 0, "away: a dropped nudge does not show when the user is back");
  const awayRecap = world();
  awayRecap.w.away = true;
  assert.equal(awayRecap.notes.offer(recap()), "away");
  assert.equal(awayRecap.notes.waiting.length, 1, "away: a recap is kept");
  awayRecap.w.away = false;
  awayRecap.notes.retry();
  assert.equal(awayRecap.w.presented.length, 1, "away: the recap shows when the user is back");
  const a = world();
  a.w.card = "approval";
  a.notes.offer(nudge());
  a.w.t += HOLD_MS.nudge + 1;
  a.w.card = null;
  a.notes.retry();
  assert.equal(a.w.presented.length, 0, "30 s is over");
  assert.equal(a.w.dropped.length, 1, "dropped, and the session told");
  const b = world();
  b.w.card = "approval";
  b.notes.offer(recap());
  b.w.t += HOLD_MS.recap - 1;
  b.notes.retry();
  assert.equal(b.w.presented.length, 0, "still waiting: the card is up");
  b.w.card = null;
  b.notes.retry();
  assert.equal(b.w.presented.length, 1, "a recap waits two minutes");
  const c = world();
  c.w.card = "approval";
  c.notes.offer(recap());
  c.w.t += HOLD_MS.recap + 1;
  c.w.card = null;
  c.notes.retry();
  assert.equal(c.w.presented.length, 0, "dropped silently after 2 minutes");
});

test("a refusal that will not pass is no waiting: the switch off, a muted kind, a session that has had its nudge, a recap that was already given", () => {
  const off = world({ on: false });
  assert.equal(off.notes.offer(nudge()), "off");
  assert.equal(off.notes.waiting.length, 0);
  const muted = world({ dismissals: { "stuck.loop": 2 } });
  assert.equal(muted.notes.offer(nudge("stuck.loop")), "muted");
  assert.equal(muted.notes.offer(nudge("stuck.silent", "k2")), "ok", "only its own kind is muted");
  const nudged = world();
  nudged.w.nudged.add("k");
  assert.equal(nudged.notes.offer(nudge("stuck.loop", "k")), "nudged");
  const given = world();
  assert.equal(given.notes.offer(recap(T0 - 600_000)), "ok");
  given.notes.dismiss();
  assert.equal(given.notes.offer(recap(T0 - 600_000)), "recapGiven", "once per away period");
  assert.equal(given.notes.offer(recap(T0 - 100)), "ok", "another away period has its own");
  assert.equal(given.notes.waiting.length, 0);
});

test("one note at a time: another is busy, a recap replaces a nudge nobody has seen, and a nudge waits a minute after any note", () => {
  const { w, notes } = world();
  notes.offer(nudge("stuck.silent", "a"));
  assert.equal(notes.offer(nudge("stuck.waiting", "b")), "busy");
  assert.equal(notes.waiting.length, 1);
  assert.equal(notes.offer(recap()), "ok", "a recap replaces a nudge that was not seen");
  assert.equal(w.presented.at(-1).kind, "recap");
  const seen = world();
  seen.notes.offer(nudge());
  seen.notes.hovered();
  assert.equal(seen.notes.offer(recap()), "busy", "a nudge the user has seen is not replaced");
  const gap = world();
  gap.notes.offer(nudge("stuck.loop", "x"));
  gap.notes.dismiss();
  gap.w.t += NOTE_GAP_MS - 1;
  assert.equal(gap.notes.offer(nudge("stuck.silent", "y")), "recent");
  gap.w.t += 2;
  gap.notes.retry();
  assert.equal(gap.w.presented.length, 2, "a minute after, the held nudge shows");
  assert.equal(gap.notes.offer(recap()), "ok", "a recap is not held back by the gap");
});

test("a click on Not now, OK or × is a dismissal; two mute the kind; folding the island unseen is none", () => {
  const { w, notes } = world();
  notes.offer(nudge("stuck.errors", "k"));
  notes.dismiss();
  assert.deepEqual(w.dismissed, ["stuck.errors"]);
  assert.equal(notes.current, null);
  notes.dismiss();
  assert.deepEqual(w.dismissed, ["stuck.errors"], "nothing on screen: nothing dismissed");
  w.t += 2 * MIN;
  notes.offer(nudge("stuck.errors", "k2"));
  w.onScreen = -1;
  notes.stateChanged();
  assert.equal(notes.current, null, "the island moved on: the note is forgotten");
  assert.deepEqual(w.dismissed, ["stuck.errors"], "folded unseen: not counted");
  w.onScreen = null;
  w.t += 2 * MIN;
  assert.equal(notes.offer(nudge("stuck.errors", "k3")), "ok");
  notes.dismiss();
  assert.equal(w.settings.dismissals["stuck.errors"], 2);
  assert.equal(notes.offer(nudge("stuck.errors", "k4")), "muted", "two dismissals mute it");
  w.settings = cleanSidekickSettings({ ...w.settings, dismissals: { ...w.settings.dismissals, "stuck.errors": 0 } });
  w.t += 2 * MIN;
  assert.equal(notes.offer(nudge("stuck.errors", "k5")), "ok", "Unmute in Settings: it shows again");
});

test("a dismissal does not show a held note by itself: the island collapses first, then the held note may show (noteCollapsed)", () => {
  const { w, notes } = world();
  notes.offer(nudge("stuck.loop", "k1"));
  notes.hovered();
  assert.equal(notes.offer(recap()), "busy", "a recap waits while the nudge on screen is seen");
  w.t += 2000;
  notes.dismiss();
  assert.equal(w.presented.length, 1, "the dismissal does not present the held recap: the collapse comes first");
  notes.retry();
  assert.equal(w.presented.length, 2, "after the collapse the held recap shows");
  assert.equal(w.presented[1].kind, "recap");
});

test("a note folded away unseen is reported to the controller, which does not count it as given", () => {
  const { w, notes } = world();
  notes.offer(nudge("stuck.loop", "k"));
  assert.equal(w.shown.length, 1);
  w.onScreen = -1;
  notes.stateChanged();
  assert.equal(notes.current, null, "folded: the note is forgotten");
  assert.deepEqual(w.folded.map((n) => n.key), ["k"], "and reported, so the session is not given its nudge");
  assert.deepEqual(w.dismissed, [], "folding is not a dismissal");
});

test("the controller: a nudge folded away unseen leaves its session's nudge unused", () => {
  const w = { t: T0, presented: [], onScreen: true, saved: [] };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", idleSeconds: async () => null, settings: () => cleanSidekickSettings(null), saveSettings: (s) => w.saved.push(s),
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => w.onScreen }, present: (n) => w.presented.push(n),
    updated: () => {}, timer: { set: () => 1, clear: () => {} },
  });
  const loop = () => { for (let i = 0; i < 4; i++) { w.t += 5000; sk.hook({ hook_event_name: "PostToolUse", session_id: "S1", cwd: "C:\\work\\app", tool_name: "Bash", tool_input: { command: "npm test" } }); } };
  loop();
  assert.equal(w.presented.length, 1);
  assert.notEqual(sk.ledger.snapshot.sessions[0].nudgedAt, null, "shown: given");
  w.onScreen = false;
  sk.stateChanged();
  assert.equal(sk.ledger.snapshot.sessions[0].nudgedAt, null, "folded unseen: not given");
});

test("the island moving to the note is not the island moving away from it", () => {
  const w = { onScreen: false };
  let notes;
  notes = new Notes({
    now: () => T0, settings: () => cleanSidekickSettings(null),
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, away: () => false, onScreen: () => w.onScreen },
    nudged: () => false, valid: () => true, updated: () => {}, shown: () => {}, dropped: () => {}, folded: () => {}, dismissed: () => {},
    // Opening the island notifies the app's state several times before the note's view is up: those notifications must not forget the note.
    present: () => { notes.stateChanged(); notes.stateChanged(); w.onScreen = true; },
  });
  notes.offer(nudge());
  assert.notEqual(notes.current, null);
  notes.stateChanged();
  assert.notEqual(notes.current, null, "on screen now");
});

test("the gate's world: a card is a pending approval, a chat card or the question view; the island is busy on every view but the quiet ones", () => {
  const base = { mode: "hidden", view: "overview", pendingApproval: null, chatApprovals: { length: 0 }, tasks: [], sidekickNoteId: null };
  let s = base;
  const w = worldOf(() => s);
  assert.equal(w.card(), null);
  s = { ...base, pendingApproval: {} };
  assert.equal(w.card(), "approval");
  s = { ...base, chatApprovals: { length: 1 } };
  assert.equal(w.card(), "approval");
  s = { ...base, mode: "expanded", view: "question" };
  assert.equal(w.card(), "question");
  s = { ...base, mode: "compact", view: "question" };
  assert.equal(w.card(), null, "a question that is not on screen is not in front");
  s = { ...base, mode: "expanded", view: "approval", pendingApproval: {} };
  assert.equal(w.ownCard(), true);
  s = { ...base, mode: "hidden", view: "approval", pendingApproval: {} };
  assert.equal(w.ownCard(), false, "the island is hidden: the card is not on screen");
  assert.equal(w.typing(), false);
  for (const view of ["prompt", "upload", "uploading", "choose", "settings", "note", "mail", "result", "confused"]) { s = { ...base, mode: "expanded", view }; assert.equal(w.typing(), true, view); }
  for (const view of QUIET_VIEWS) { s = { ...base, mode: "expanded", view }; assert.equal(w.typing(), false, view); }
  s = { ...base, mode: "compact", view: "prompt" };
  assert.equal(w.typing(), false, "a compact island has nothing open in it");
  s = { ...base, tasks: [{ state: "working" }, { state: "ratelimit" }] };
  assert.equal(w.ratelimit(), true);
  s = { ...base, mode: "expanded", view: "sidekick", sidekickNoteId: 4 };
  assert.deepEqual([w.onScreen(4), w.onScreen(5)], [true, false]);
  s = { ...base, mode: "compact", view: "sidekick", sidekickNoteId: 4 };
  assert.equal(w.onScreen(4), false);
});

test("the Sidekick offers a recap when the user comes back, if an agent did something", () => {
  const w = { t: T0, away: false, presented: [], saved: [] };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", idleSeconds: async () => null, settings: () => cleanSidekickSettings(null), saveSettings: (s) => w.saved.push(s),
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true }, present: (n) => w.presented.push(n),
    updated: () => {}, timer: { set: () => 1, clear: () => {} },
  });
  const hook = (name, extra = {}) => ({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
  sk.presenceSignal("lock");
  w.t += 10_000;
  sk.hook(hook("PostToolUse", { tool_name: "Edit", tool_input: { file_path: "C:\\work\\app\\a.ts" } }));
  w.t += 5 * MIN;
  sk.hook(hook("Stop"));
  sk.presenceSignal("unlock");
  assert.equal(w.presented.length, 1);
  const note = w.presented[0];
  assert.equal(note.kind, "recap");
  assert.match(note.lines[0], /^While you were away, Claude Code in app ran 1 step, edited a\.ts, and finished\.$/);
  assert.equal(note.awaySince, T0);
  assert.equal(note.facts[0].agent, "Claude Code");
  // A second lock and unlock in a hurry gives no recap, and neither does an away in which nothing happened.
  sk.presenceSignal("lock");
  w.t += 60_000;
  sk.presenceSignal("unlock");
  assert.equal(w.presented.length, 1);
  sk.noteDismissed();
  assert.equal(w.saved.length, 1);
  assert.equal(w.saved[0].dismissals.recap, 1, "the OK is a dismissal of the recap");
});

test("an approval click is recorded against the request's own agent, so a non-Claude request's session clears its wait", () => {
  const w = { t: T0 };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", idleSeconds: async () => null, settings: () => cleanSidekickSettings(null), saveSettings: () => {},
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true }, present: () => {},
    updated: () => {}, timer: { set: () => 1, clear: () => {} },
  });
  const gemini = () => sk.ledger.snapshot.sessions.find((s) => s.sessionId === "G1");
  sk.hook({ hook_event_name: "PermissionRequest", session_id: "G1", nm_agent: "gemini", cwd: "C:\\work\\app", tool_name: "run_shell_command", tool_input: { command: "ls" } });
  assert.notEqual(gemini().pendingApprovalAt, null, "the request waits");
  sk.approvalAnswered("agent_gemini", "G1");
  assert.equal(gemini().pendingApprovalAt, null, "the click on its own pill clears the wait");
  assert.match(source("island/hooks.ts"), /pillId: agentId,/, "the request carries the pill it belongs to");
  assert.match(source("island/island.ts"), /Hub\.sk\?\.approvalAnswered\(req\.pillId, req\.sessionId\);/, "the click names the request's own pill, not Claude Code's");
});

test("the Sidekick's view grows by a line of text per line and stops at 280", () => {
  assert.deepEqual([0, 1, 2, 3, 4, 20].map(sidekickHeight), [160, 160, 190, 220, 250, 280]);
});

test("the wiring: the island's peek shows the note, every click on it is a dismissal, folding is not, State changes and Settings changes reach the Sidekick", () => {
  const env = source("sidekick/appenv.ts");
  assert.match(env, /State\.sidekickNote = note;\s*island\.alert\("sidekick"\);/);
  assert.doesNotMatch(env, /isPinned|holdOpen/, "a note never pins the island");
  const views = source("views/views.ts");
  assert.match(views, /btn\("OK", "primary", \(\) => actions\.sidekickDismiss\(\)\)/);
  assert.match(views, /btn\("Not now", "secondary", \(\) => actions\.sidekickDismiss\(\)\)/);
  assert.match(views, /class: "icon-btn jump", title: "Dismiss", onclick: \(\) => actions\.sidekickDismiss\(\)/);
  assert.match(views, /if \(act\) row\.append\(btn\(act\.label, "primary", \(\) => actions\.sidekickOpen\(\)\)\);/, "Open terminal (or Open Claude) is not a dismissal");
  assert.match(views, /map\.set\("sidekick", buildSidekick\(actions\)\);/);
  const island = source("island/island.ts");
  assert.match(island, /sidekickDismiss: \(\) => \{\s*Hub\.sk\?\.noteDismissed\(\);\s*this\.collapse\(\);\s*Hub\.sk\?\.noteCollapsed\(\);/, "the held notes get their look after the collapse, never before it");
  assert.match(island, /Hub\.sk\?\.noteHovered\(\);/);
  const main = source("main.ts");
  assert.match(main, /State\.subscribe\(\(\) => Hub\.sk\?\.stateChanged\(\)\);/);
  assert.match(main, /Hub\.sk\?\.settingsChanged\(\);/);
  assert.match(source("core/layout.ts"), /sidekick: \{ height: 160, botX: 62, botY: null, botDiameter: 56, agentMode: "column" \}/);
});

test("a recap of more than three agents ends in a row of three dots, not a count", () => {
  const w = { t: T0, presented: [] };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", idleSeconds: async () => null, settings: () => cleanSidekickSettings(null), saveSettings: () => {},
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true },
    present: (n) => w.presented.push(n), updated: () => {}, timer: { set: () => 1, clear: () => {} },
  });
  sk.presenceSignal("lock");
  for (const agent of ["gemini", "antigravity", "alpha", "beta", "gamma"]) {
    w.t += 1000;
    sk.hook({ hook_event_name: "PostToolUse", session_id: `s-${agent}`, nm_agent: agent, cwd: "C:\\work\\app", tool_name: "run_shell_command", tool_input: { command: "ls" } });
  }
  w.t += 5 * MIN;
  sk.presenceSignal("unlock");
  const lines = w.presented[0].lines;
  assert.equal(lines.length, 4);
  assert.equal(lines[3], "…");
  assert.ok(lines.slice(0, 3).every((l) => l.startsWith("While you were away, ")));
  assert.equal(w.presented[0].facts.length, 5, "the facts are the contract's: five agents");
});

test("the cleanup: no empty dropped callback in the controller, its State listeners keep their catch (with the reason, and no log), and one open path for Open terminal", () => {
  const ctl = source("sidekick/controller.ts");
  assert.doesNotMatch(ctl, /dropped: \(\) => \{/, "the empty dropped callback is gone");
  assert.match(source("sidekick/notes.ts"), /dropped\?\(note: Note\): void;/, "the notes report a dropped note only when someone listens");
  const catches = /(stateChanged|settingsChanged)\(\): void \{\s*try \{[\s\S]*?\} catch \{\s*\/\/ The sidekick never breaks the island[^\n]*\n\s*\}\n  \}/g;
  assert.deepEqual([...ctl.matchAll(catches)].map((m) => m[1]), ["stateChanged", "settingsChanged"], "both State listeners catch, with the reason written next to the catch");
  assert.doesNotMatch(ctl, /console\./, "and nothing is logged");
  const island = source("island/island.ts");
  assert.match(island, /private openTerminalIn\(cwd: string \| null\)/, "one function opens a project in VS Code");
  assert.match(island, /sidekickOpen: \(\) => \{\s*const id = State\.sidekickNote\?\.agentId;\s*this\.openAgent\(/);
  assert.match(island, /else this\.openTerminalIn\(cwd\);/, "and the one path to VS Code is still openTerminalIn");
  assert.doesNotMatch(island, /sidekickOpen: \(\) => \{[^}]*Bridge\.openInVSCode/, "the Sidekick's note does not call VS Code itself");
});
