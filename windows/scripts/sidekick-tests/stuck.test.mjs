import test from "node:test";
import assert from "node:assert/strict";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { StuckClock, MAX_DELAY_MS } from "../../src/sidekick/stuckclock.ts";
import { STUCK, cleanSidekickSettings } from "../../src/sidekick/core.ts";
import { source } from "./util.mjs";

const T0 = 20_000_000;
const MIN = 60_000;

/** A Sidekick on a clock and a timer queue the test turns by hand; the world (a card, the rate limit) is set by hand too. */
function rig(platform = "windows", settings = {}) {
  const w = { t: T0, timers: new Map(), id: 1, sets: 0, card: null, ownCard: false, ratelimit: false, throwOnce: false, throwLapsed: false, typing: false, onScreen: true, settings: cleanSidekickSettings(settings), presented: [], updated: [], marks: new Map(), lapsed: 0 };
  const sk = new Sidekick({
    now: () => w.t, platform, idleSeconds: async () => null,
    settings: () => w.settings, saveSettings: (s) => { w.settings = s; },
    world: { ratelimit: () => { if (w.throwOnce) { w.throwOnce = false; throw new Error("one look fails"); } return w.ratelimit; }, card: () => w.card, ownCard: () => w.ownCard, typing: () => w.typing, onScreen: () => w.onScreen },
    present: (n) => w.presented.push(n), updated: (n) => w.updated.push(n),
    timer: { set: (fn, ms) => { const id = w.id++; w.sets++; w.timers.set(id, { fn, at: w.t + ms }); return id; }, clear: (id) => { w.timers.delete(id); } },
    stepBackEnd: (id) => w.marks.get(id) ?? null,
    focusLapseAt: () => (w.marks.size ? Math.min(...w.marks.values()) : null),
    focusLapsed: () => { w.lapsed++; if (w.throwLapsed) throw new Error("listener fails"); },
  });
  const hook = (name, extra = {}) => sk.hook({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
  const tool = (cmd, name = "PostToolUse") => hook(name, { tool_name: "Bash", tool_input: { command: cmd } });
  const advance = (ms) => {
    const end = w.t + ms;
    for (;;) {
      const due = [...w.timers.entries()].filter(([, x]) => x.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      w.t = due[1].at; w.timers.delete(due[0]); due[1].fn();
    }
    w.t = end;
  };
  return { w, sk, hook, tool, advance, texts: () => w.presented.map((n) => n.lines[0]) };
}

test("a loop: the same step four times, once per session, in the contract's words, with no timer of its own for it", () => {
  const { w, tool, advance, texts } = rig();
  for (let i = 0; i < 3; i++) { tool("npm test"); advance(5000); }
  assert.deepEqual(texts(), []);
  tool("npm test");
  assert.deepEqual(texts(), ["Claude Code has run the same step 4 times."]);
  assert.equal(w.presented[0].kind, "stuck.loop");
  advance(2 * MIN);
  for (let i = 0; i < 8; i++) { tool("npm test"); advance(1000); }
  assert.equal(texts().length, 1, "a session is nudged once");
});

test("three errors in a row, Claude Code only", () => {
  const { tool, advance, texts } = rig();
  for (let i = 0; i < 3; i++) { tool(`bad ${i}`, "PostToolUseFailure"); advance(2000); }
  assert.deepEqual(texts(), ["Claude Code hit 3 errors in a row."]);
  const other = rig();
  for (let i = 0; i < 3; i++) { other.sk.hook({ hook_event_name: "PostToolUseFailure", session_id: "g", nm_agent: "gemini", cwd: "C:\\w", tool_name: "run_shell_command", tool_input: { command: `x${i}` } }); other.advance(2000); }
  assert.deepEqual(other.texts(), [], "Gemini sends no failure event worth a nudge");
});

test("waiting for your OK: a minute after the request, if its card is not on screen; the words change in place at the give-up, not a second nudge", () => {
  const { w, hook, advance, texts } = rig("windows");
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  assert.ok(w.timers.size === 1, "one timer, for the nearest deadline");
  advance(59_000);
  assert.deepEqual(texts(), []);
  advance(1000);
  assert.deepEqual(texts(), ["Claude Code is still waiting for your OK."]);
  assert.equal(w.presented.length, 1);
  advance(49_000);
  assert.equal(w.updated.length, 0, "the app has not given up yet at 109 s");
  advance(1000);
  assert.equal(w.presented.length, 1, "no second nudge");
  assert.deepEqual(w.updated.map((n) => n.lines[0]), ["Claude Code is waiting for your OK in the terminal."], "110 s on Windows: the same note, other words");
  assert.equal(w.updated[0].id, w.presented[0].id);
});

test("the Linux give-up is 110 s too, and a card on screen means no waiting nudge until the card hides", () => {
  assert.equal(STUCK.GIVE_UP_MS.linux, 110_000);
  const { w, sk, hook, advance, texts } = rig("linux");
  w.ownCard = true;
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  advance(5 * MIN);
  assert.deepEqual(texts(), [], "its own card is on screen");
  w.ownCard = false;
  sk.stateChanged();
  assert.deepEqual(texts(), ["Claude Code is waiting for your OK in the terminal."], "the card hid long after the give-up: the words are the later ones, once");
});

test("quiet: five minutes after a finished step, fifteen after a step that never ended; the clock is set to the deadline and fires once", () => {
  const { w, sk, tool, advance, texts } = rig();
  assert.equal(sk.clock.armed, false, "nothing live: no timer at all");
  tool("ls", "PostToolUse");
  assert.equal(sk.clock.armed, true);
  assert.equal(sk.clock.due, T0 + 5 * MIN);
  advance(5 * MIN - 1);
  assert.deepEqual(texts(), []);
  advance(1);
  assert.deepEqual(texts(), ["Claude Code has been quiet for 5 minutes."]);
  assert.equal(sk.clock.armed, false, "after the one nudge the session has nothing left to wait for");
  assert.equal(w.timers.size, 0);
  const b = rig();
  b.tool("long build", "PreToolUse");
  b.advance(14 * MIN);
  assert.deepEqual(b.texts(), []);
  b.advance(1 * MIN);
  assert.deepEqual(b.texts(), ["Claude Code has been quiet for 15 minutes."]);
});

test("every event sets the clock again to the new nearest deadline, and one timer is all there ever is", () => {
  const { w, sk, tool, advance } = rig();
  tool("ls");
  const first = sk.clock.due;
  advance(2 * MIN);
  tool("ls again");
  assert.equal(sk.clock.due, first + 2 * MIN, "pushed back by the new event");
  assert.equal(w.timers.size, 1);
  for (let i = 0; i < 30; i++) { advance(1000); tool(`step ${i}`); assert.ok(w.timers.size <= 1); }
});

test("away, a rate limit and the switch: no nudge and no clock; when they end the rules are asked again at once", () => {
  const { w, sk, tool, advance, texts } = rig();
  tool("ls");
  sk.presenceSignal("lock");
  assert.equal(sk.clock.armed, false, "away: no deadline");
  advance(10 * MIN);
  assert.deepEqual(texts(), []);
  sk.presenceSignal("unlock");
  assert.equal(w.presented[0].kind, "recap", "back: the recap comes first");
  assert.equal(sk.notes.waiting.length, 0, "the nudge that fell due while away is dropped, not saved for later");
  sk.noteDismissed();
  advance(10 * MIN);
  assert.equal(w.presented.length, 1, "and it does not come back");
  tool("ls again");
  advance(5 * MIN);
  assert.ok(texts().at(-1).startsWith("Claude Code has been quiet for"), "a new event is a new thing: its nudge is given as usual");
  const r = rig();
  r.tool("ls");
  r.w.ratelimit = true;
  r.sk.stateChanged();
  assert.equal(r.sk.clock.armed, false);
  r.advance(10 * MIN);
  assert.deepEqual(r.texts(), []);
  r.w.ratelimit = false;
  r.sk.stateChanged();
  assert.equal(r.texts().length, 1, "the rate limit ended: asked again");
  const off = rig("windows", { on: false });
  off.tool("ls");
  assert.equal(off.sk.clock.armed, false);
  off.advance(10 * MIN);
  assert.deepEqual(off.texts(), []);
  off.w.settings = cleanSidekickSettings({ on: true });
  off.sk.settingsChanged();
  assert.equal(off.texts().length, 1, "the switch came on: asked at once");
  assert.equal(w.sets > 0, true);
});

test("a nudge that waited for the gate is shown only if it is still true; one that ran out of time was never given, and a new event brings a new one", () => {
  const { w, sk, tool, advance, texts } = rig();
  tool("ls");
  w.typing = true;
  advance(5 * MIN);
  assert.deepEqual(texts(), [], "held: the user is in the middle of something");
  tool("ls again");
  w.typing = false;
  sk.stateChanged();
  assert.deepEqual(texts(), [], "the agent spoke again: the quiet nudge is no longer true and is forgotten");
  const gone = rig();
  gone.tool("ls");
  gone.w.typing = true;
  gone.advance(5 * MIN + 31_000);
  gone.w.typing = false;
  gone.sk.stateChanged();
  assert.deepEqual(gone.texts(), [], "30 s of waiting is over");
  gone.advance(60 * MIN);
  assert.deepEqual(gone.texts(), [], "dropped: not said later, with nothing new");
  gone.tool("ls again");
  gone.advance(5 * MIN + 1000);
  assert.equal(gone.texts().length, 1, "it counted as given only once shown: the session is nudged for the next quiet");
});

test("two dismissals of a kind mute it; the click on a nudge is stored through the settings", () => {
  const { w, sk, tool, advance, texts } = rig();
  tool("ls");
  advance(5 * MIN);
  assert.equal(texts().length, 1);
  sk.noteDismissed();
  assert.equal(w.settings.dismissals["stuck.silent"], 1);
  advance(2 * MIN);
  w.settings = cleanSidekickSettings({ dismissals: { "stuck.silent": 2 } });
  const m = rig("windows", { dismissals: { "stuck.silent": 2 } });
  m.tool("ls");
  m.advance(10 * MIN);
  assert.deepEqual(m.texts(), [], "muted");
});

test("the clock itself: one timer, the same deadline keeps it, a new one replaces it, null or a time that is not a time stops it, and a far deadline is set for the longest delay", () => {
  const w = { t: 1000, sets: [], cleared: [], fired: 0 };
  const c = new StuckClock({ now: () => w.t, set: (fn, ms) => { w.sets.push(ms); return w.sets.length; }, clear: (id) => w.cleared.push(id) }, () => { w.fired++; });
  assert.equal(c.armed, false);
  c.arm(5000);
  c.arm(5000);
  assert.deepEqual(w.sets, [4000], "the same deadline: no second timer");
  c.arm(9000);
  assert.deepEqual(w.sets, [4000, 8000]);
  assert.deepEqual(w.cleared, [1]);
  for (const bad of [null, Number.NaN, Number.POSITIVE_INFINITY]) c.arm(bad);
  assert.equal(c.armed, false);
  c.arm(500);
  assert.equal(w.sets.at(-1), 0, "a deadline in the past fires at once");
  c.arm(1000 + 60 * 24 * 3600 * 1000);
  assert.equal(w.sets.at(-1), MAX_DELAY_MS);
});

test("no interval, no polling: the Sidekick's one timer is the stuck clock's, and the controller sets it only through the clock", () => {
  const ctl = source("sidekick/controller.ts");
  assert.doesNotMatch(ctl, /setInterval|requestAnimationFrame|setTimeout/);
  assert.equal(ctl.split("env.timer.set").length - 1, 1, "the timer is asked for in one place");
  assert.match(source("sidekick/appenv.ts"), /timer: \{ set: \(fn, ms\) => window\.setTimeout\(fn, ms\), clear: \(id\) => window\.clearTimeout\(id\) \}/);
  assert.doesNotMatch(source("sidekick/stuckclock.ts"), /setInterval/);
});

test("two quiet sessions, the first refused: the rules are asked again without it, so the second is offered too", () => {
  const { w, sk, hook, advance } = rig();
  w.card = "approval";
  hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "ls" } });
  hook("PostToolUse", { session_id: "S2", tool_name: "Bash", tool_input: { command: "ls" } });
  advance(5 * MIN + 2000);
  const keys = sk.notes.waiting.map((n) => n.key).sort();
  assert.deepEqual(keys, ["integration_claude|S1", "integration_claude|S2"], "the first is held for the card, and the second is offered and held too");
});

test("a quiet session that fell due while the user was away is dropped, and a quiet session that falls due after the return is offered", () => {
  const { w, sk, hook, advance, tool } = rig();
  tool("ls", "PostToolUse");
  advance(30_000);
  hook("PostToolUse", { session_id: "S2", tool_name: "Bash", tool_input: { command: "ls" } });
  advance(30_000);
  sk.presenceSignal("lock");
  advance(4 * MIN + 1000);
  sk.presenceSignal("unlock");
  assert.deepEqual(w.presented.filter((n) => n.kind === "stuck.silent"), [], "S1 fell due while away: dropped, and S2 is not due yet");
  advance(MIN);
  const quiet = w.presented.filter((n) => n.kind === "stuck.silent");
  assert.deepEqual(quiet.map((n) => n.key), ["integration_claude|S2"], "S2 falls due after the return: it is offered");
});

test("a muted kind is not chosen at all: a loop muted twice does not hide a waiting session", () => {
  const { w, hook, tool, advance } = rig("windows", { dismissals: { "stuck.loop": 2 } });
  for (let i = 0; i < 4; i++) { tool("npm test"); advance(5000); }
  hook("PermissionRequest", { session_id: "S2", tool_name: "Bash", tool_input: { command: "rm x" } });
  advance(STUCK.WAIT_MS + 1000);
  assert.deepEqual(w.presented.map((n) => n.kind), ["stuck.waiting"], "the waiting session shows; the muted loop is never chosen");
  assert.equal(w.presented[0].key, "integration_claude|S2");
});

test("a muted loop does not mask the quiet nudge of the same session: the loop is skipped, and the quiet one shows once it falls due", () => {
  const { w, tool, advance } = rig("windows", { dismissals: { "stuck.loop": 2 } });
  for (let i = 0; i < 4; i++) { tool("npm test"); advance(5000); }
  advance(5 * MIN);
  assert.deepEqual(w.presented.map((n) => n.kind), ["stuck.silent"], "the loop is muted and skipped; the same session's quiet nudge is offered");
  assert.equal(w.presented[0].key, "integration_claude|S1");
});

test("no timer while the user is away or the agent is rate-limited: the give-up deadline of a waiting nudge on screen is not armed then", () => {
  const { w, sk, hook, advance } = rig("windows");
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  advance(STUCK.WAIT_MS + 1000);
  assert.equal(w.presented.length, 1, "the waiting nudge is on screen");
  sk.presenceSignal("lock");
  assert.equal(w.timers.size, 0, "away: no timer, not even for the give-up");
  sk.presenceSignal("unlock");
  w.ratelimit = true;
  sk.evaluate();
  assert.equal(w.timers.size, 0, "rate-limited: no timer");
});

test("a settings change asks the rules once", () => {
  const { sk } = rig();
  let asked = 0;
  const once = sk.evaluate.bind(sk);
  sk.evaluate = () => { asked++; once(); };
  sk.settingsChanged();
  assert.equal(asked, 1, "one evaluate after the notes have their look");
});

/** A Sidekick whose idle reads the test answers by hand: each call is written down, and `wait` is the timeout the test fires. */
function idleRig(wait = () => new Promise(() => {})) {
  const w = { t: T0, reads: [], waits: [], resolvers: [] };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows",
    idleSeconds: () => { w.reads.push(w.t); return new Promise((r) => w.resolvers.push(r)); },
    settings: () => cleanSidekickSettings(null), saveSettings: () => {},
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true },
    present: () => {}, updated: () => {}, timer: { set: () => 1, clear: () => {} },
    wait: (ms, signal) => { w.waits.push(ms); return wait(ms, signal); },
  });
  return { w, sk, hook: (name) => sk.hook({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", tool_name: "Bash", tool_input: { command: "ls" } }) };
}
const flush = () => new Promise((r) => setTimeout(r, 0));

test("an unlock during a slow idle reading is not dropped: one more reading follows it", async () => {
  const { w, sk, hook } = idleRig();
  hook("PostToolUse");
  assert.equal(w.reads.length, 1, "the hook asks for a reading");
  sk.presenceSignal("unlock");
  assert.equal(w.reads.length, 1, "the unlock waits for the reading in flight");
  w.resolvers[0](null);
  await flush();
  assert.equal(w.reads.length, 2, "and the unlock's own reading follows it");
});

test("an idle reading that never answers ends at the timeout (about 3 s): no reading, and the next one is asked for", async () => {
  const { w, sk, hook } = idleRig(() => Promise.resolve());
  hook("PostToolUse");
  await flush();
  assert.equal(w.reads.length, 1);
  assert.equal(w.waits.length, 1, "the reading is raced against one timeout");
  assert.ok(w.waits[0] > 0 && w.waits[0] <= 3000, `the timeout is about 3 s, not ${w.waits[0]}`);
  w.t += 6000;
  sk.islandOpened();
  assert.equal(w.reads.length, 2, "the timed-out reading cleared the flag: the next one is asked for");
});

/** An idle rig whose timeout is a fake timer that writes down every set and every clear (the clear is the abort of the signal the Sidekick hands over). */
function timerRig() {
  const log = { sets: [], clears: [] };
  const rig = idleRig((ms, signal) => {
    const id = log.sets.length + 1;
    log.sets.push(id);
    signal?.addEventListener("abort", () => log.clears.push(id));
    return new Promise(() => {});
  });
  return { ...rig, log };
}

test("an idle reading that answers in time leaves no timer behind: every timeout it set is cleared", async () => {
  const { w, hook, log } = timerRig();
  hook("PostToolUse");
  assert.equal(log.sets.length, 1, "the reading is raced against one timeout");
  assert.deepEqual(log.clears, [], "still running while the reading is on its way");
  w.resolvers[0](12);
  await flush();
  assert.deepEqual(log.clears, log.sets, "the reading won: its timeout is cleared");
});

test("a timed-out idle reading clears its timeout too, and a reading that fails is no reading", async () => {
  const { w, sk, hook, log } = timerRig();
  hook("PostToolUse");
  w.resolvers[0](Promise.reject(new Error("no")));
  await flush();
  assert.deepEqual(log.clears, log.sets, "a failing reading: cleared");
  w.t += 6000;
  sk.islandOpened();
  assert.equal(log.sets.length, 2, "and the next reading is asked for, with its own timeout");
});

test("an idle sample that finds the user away stops the stuck clock: no timer is armed while away", async () => {
  const w = { t: T0, timers: new Map(), id: 1, idle: 0 };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", idleSeconds: async () => w.idle,
    settings: () => cleanSidekickSettings(null), saveSettings: () => {},
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true },
    present: () => {}, updated: () => {}, wait: () => new Promise(() => {}),
    timer: { set: (fn, ms) => { const id = w.id++; w.timers.set(id, { fn, at: w.t + ms }); return id; }, clear: (id) => { w.timers.delete(id); } },
  });
  sk.hook({ hook_event_name: "PostToolUse", session_id: "S1", cwd: "C:\\work\\app", tool_name: "Bash", tool_input: { command: "npm test" } });
  await flush();
  assert.equal(w.timers.size, 1, "the quiet deadline of the running session is armed");
  w.t += 4 * MIN;
  w.idle = 300;
  await sk.sampleIdle(true);
  assert.equal(w.timers.size, 0, "the sample says the user is away: the armed clock is stopped, no timer while away");
});

test("the idle timeout is a cancellable one in the island's env: the clear is the clearTimeout of the same id", () => {
  assert.match(source("sidekick/appenv.ts"), /wait: \(ms, signal\) => new Promise<void>\(\(resolve\) => \{\s*const id = window\.setTimeout\(resolve, ms\);\s*signal\.addEventListener\("abort", \(\) => window\.clearTimeout\(id\), \{ once: true \}\);/);
});

test("a stepped-back session gets no waiting nudge while its mark lives; another session's still comes", () => {
  const { w, hook, advance, texts } = rig("windows");
  w.marks.set("S1", T0 + 10 * MIN);
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  hook("PermissionRequest", { session_id: "S2", tool_name: "Bash", tool_input: { command: "rm y" } });
  advance(MIN);
  const waiting = w.presented.filter((n) => n.kind === "stuck.waiting");
  assert.equal(waiting.length, 1, "exactly one waiting nudge");
  assert.equal(waiting[0].key, "integration_claude|S2", "about S2, not the stepped-back S1");
  assert.equal(texts().length, 1);
});

test("the mark's end wakes the clock once, even with the switch off, and tells the app once", () => {
  const { w, sk, hook, advance } = rig("windows", { on: false });
  w.marks.set("S1", T0 + 10 * MIN);
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  assert.equal(w.timers.size, 1, "one timer, for the mark's end");
  assert.equal(sk.clock.due, T0 + 10 * MIN);
  advance(10 * MIN);
  assert.equal(w.lapsed, 1, "the app is told at the lapse");
  w.marks.delete("S1");
  advance(30 * MIN);
  assert.equal(w.lapsed, 1, "once, never again");
  assert.equal(w.timers.size, 0, "no timer armed after the lapse");
});

test("two marks: the clock is armed for the earliest, then for the next", () => {
  const { w, sk, hook, advance } = rig("windows");
  w.marks.set("S1", T0 + 5 * MIN);
  w.marks.set("S2", T0 + 8 * MIN);
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  hook("PermissionRequest", { session_id: "S2", tool_name: "Bash", tool_input: { command: "rm y" } });
  // Precondition: both sessions are held by their marks, so no waiting nudge is offered before the first lapse. If that ever changes, this fails here, not below.
  assert.equal(w.presented.length, 0, "precondition: no nudge is offered while both marks live");
  assert.equal(sk.clock.due, T0 + 5 * MIN, "armed for the earliest mark");
  advance(5 * MIN - 1);
  assert.equal(sk.clock.due, T0 + 5 * MIN);
  w.marks.delete("S1");
  advance(1);
  assert.equal(w.lapsed, 1);
  assert.equal(sk.clock.due, T0 + 8 * MIN, "then for the next one");
});

test("a stepped-back session's waiting nudge comes back once its mark has lapsed: the look at the lapse still holds it, the next look offers it", () => {
  const { w, sk, hook, advance } = rig("windows");
  w.marks.set("S1", T0 + 10 * MIN);
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  advance(10 * MIN);
  assert.equal(w.presented.filter((n) => n.kind === "stuck.waiting").length, 0, "the lapse's own look: the mark is still in the rig, so S1 is held");
  w.marks.delete("S1");
  sk.evaluate();
  const waiting = w.presented.filter((n) => n.kind === "stuck.waiting");
  assert.equal(waiting.length, 1, "S1's waiting nudge arrives once the mark is gone");
  assert.equal(waiting[0].key, "integration_claude|S1");
});

test("a lapse redraws the app once even when a look throws in the same evaluate, and the clock is set to the next live mark's end", () => {
  const { w, sk, hook, advance } = rig("windows");
  w.marks.set("S1", T0 + 10 * MIN);
  w.marks.set("S2", T0 + 20 * MIN);
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  hook("PermissionRequest", { session_id: "S2", tool_name: "Bash", tool_input: { command: "rm y" } });
  assert.equal(sk.clock.due, T0 + 10 * MIN);
  w.marks.delete("S1");
  w.throwOnce = true;
  advance(10 * MIN);
  assert.equal(w.lapsed, 1, "the app is told at the lapse, though the look threw");
  assert.equal(sk.clock.due, T0 + 20 * MIN, "the clock is set to the next live mark's end");
  w.marks.delete("S2");
  advance(10 * MIN);
  assert.equal(w.lapsed, 2, "the second lapse is told once too");
  assert.equal(w.timers.size, 0, "and no timer is left after it");
});

test("a look that throws before its clock keeps the stuck deadline already armed: an earlier deadline survives, a later lapse does not replace it", () => {
  const { w, sk, hook } = rig("windows");
  w.marks.set("S1", T0 + 10 * MIN);
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  hook("PermissionRequest", { session_id: "S2", tool_name: "Bash", tool_input: { command: "rm y" } });
  assert.equal(sk.clock.due, T0 + MIN, "armed for S2's waiting deadline, before S1's lapse");
  w.throwOnce = true;
  sk.evaluate();
  assert.equal(sk.clock.due, T0 + MIN, "the failed look keeps the earlier stuck deadline");
});

test("a look that throws with no live mark does not cancel the stuck deadline already armed", () => {
  const { w, sk, hook } = rig("windows");
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  assert.equal(sk.clock.due, T0 + MIN);
  w.throwOnce = true;
  sk.evaluate();
  assert.equal(sk.clock.due, T0 + MIN, "the deadline is still armed");
  assert.equal(w.timers.size, 1);
});

test("a listener that throws at the lapse does not escape the look, and the clock stays armed for the next live mark", () => {
  const { w, sk, hook, advance } = rig("windows");
  w.marks.set("S1", T0 + 10 * MIN);
  w.marks.set("S2", T0 + 20 * MIN);
  hook("PermissionRequest", { tool_name: "Bash", tool_input: { command: "rm x" } });
  hook("PermissionRequest", { session_id: "S2", tool_name: "Bash", tool_input: { command: "rm y" } });
  w.marks.delete("S1");
  w.throwLapsed = true;
  assert.doesNotThrow(() => advance(10 * MIN), "the lapse's look does not throw out of the timer");
  assert.equal(w.lapsed, 1, "the listener was asked once");
  assert.equal(sk.clock.due, T0 + 20 * MIN, "the clock is still armed for the next mark's end");
});

test("the State listener never breaks the island: a world or a setting that throws does not reach State.notify", () => {
  const a = rig();
  a.w.ratelimit = false;
  Object.defineProperty(a.w, "ratelimit", { get() { throw new Error("secret-marker /home/x/file"); } });
  assert.doesNotThrow(() => a.sk.stateChanged(), "stateChanged");
  const b = rig();
  Object.defineProperty(b.w, "settings", { get() { throw new Error("secret-marker"); } });
  assert.doesNotThrow(() => b.sk.settingsChanged(), "settingsChanged");
});
