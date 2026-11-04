import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { Presence, isAwayWord } from "../../src/sidekick/presence.ts";
import { SAMPLE_GAP_MS, Sidekick } from "../../src/sidekick/controller.ts";
import { source } from "./util.mjs";

const T0 = 1_000_000;
const s = (n) => n * 1000;

test("the six words of the platform are the signals; anything else is no word", () => {
  for (const w of ["lock", "unlock", "sleep", "wake", "displayOff", "displayOn"]) assert.ok(isAwayWord(w), w);
  for (const w of ["Lock", "idle", "", null, undefined, 7, {}, ["lock"]]) assert.equal(isAwayWord(w), false, String(w));
  const p = new Presence();
  for (const w of ["idle", "Lock", 7, null]) assert.equal(p.signal(w, T0), null);
  assert.equal(p.away, false);
});

test("a lock and an unlock: away from the lock, back at the unlock, told once", () => {
  const p = new Presence();
  assert.equal(p.signal("lock", T0), null);
  assert.equal(p.away, true);
  assert.equal(p.awaySince, T0);
  assert.deepEqual(p.signal("unlock", T0 + s(300)), { awaySince: T0, awayMs: s(300) });
  assert.equal(p.away, false);
  assert.equal(p.signal("unlock", T0 + s(301)), null, "never told twice");
});

test("away holds until the last reason lets go: a lock, then the display, then an unlock, then the display on", () => {
  const p = new Presence();
  p.signal("lock", T0);
  p.signal("displayOff", T0 + s(5));
  assert.equal(p.signal("unlock", T0 + s(60)), null, "the display is still off");
  assert.deepEqual(p.signal("displayOn", T0 + s(90)), { awaySince: T0, awayMs: s(90) });
});

test("idle: 300 s of no input is away from the moment the input stopped, and a sample with input since is back at that input, not when it was noticed", () => {
  const p = new Presence();
  assert.equal(p.sample(10, T0), null);
  assert.equal(p.away, false);
  assert.equal(p.sample(400, T0 + s(5)), null);
  assert.equal(p.away, true);
  assert.equal(p.awaySince, T0 + s(5) - s(400), "the away began when the last input was");
  assert.equal(p.sample(460, T0 + s(65)), null, "still no input: still away");
  // 90 s later the system says the last input was 10 s ago: the user came back 80 s after the previous sample (65 s + 90 s - 10 s).
  const back = p.sample(10, T0 + s(155));
  assert.deepEqual(back, { awaySince: T0 + s(5) - s(400), awayMs: T0 + s(145) - (T0 + s(5) - s(400)) });
  assert.equal(p.away, false);
  assert.equal(p.sample(11, T0 + s(156)), null, "told once");
});

test("a sample between 3 and 300 s of idle, taken after nothing at all, changes nothing; a quick sample after a long one is back", () => {
  const p = new Presence();
  assert.equal(p.sample(100, T0), null);
  assert.equal(p.away, false);
  assert.equal(p.sample(500, T0 + s(400)), null);
  assert.equal(p.away, true);
  assert.deepEqual(Object.keys(p.sample(1, T0 + s(402))), ["awaySince", "awayMs"]);
});

test("a sample that is not a number from 0 up is no sample, and the previous one is kept", () => {
  const p = new Presence();
  p.sample(400, T0);
  for (const bad of [Number.NaN, Number.POSITIVE_INFINITY, -1, "400", null, undefined, {}]) assert.equal(p.sample(bad, T0 + s(10)), null, String(bad));
  assert.equal(p.sample(5, Number.NaN), null, "nor a time that is not a time");
  assert.equal(p.away, true, "nothing above ended the away");
});

test("a lock together with idle: the unlock is not enough, the idle lets go with the next sample, and the away began at the first of them", () => {
  const p = new Presence();
  p.sample(400, T0);
  p.signal("lock", T0 + s(10));
  assert.equal(p.awaySince, T0 - s(400));
  assert.equal(p.signal("unlock", T0 + s(100)), null, "idle still holds");
  const back = p.sample(2, T0 + s(101));
  assert.equal(back.awaySince, T0 - s(400));
  assert.equal(back.awayMs, T0 + s(99) - (T0 - s(400)), "back at the input, 2 s before the sample");
});

test("a fuzz of signals and samples: a return is told exactly when the last reason lets go, never twice in a row and never while away", () => {
  let seed = 7;
  const rnd = (n) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  for (let round = 0; round < 40; round++) {
    const p = new Presence();
    let t = T0, idle = 0, lastReturn = false, returns = 0, aways = 0, wasAway = false;
    for (let i = 0; i < 300; i++) {
      t += rnd(200) * 1000;
      idle = rnd(3) === 0 ? rnd(8) : idle + (rnd(2) ? rnd(120) : 0);
      const r = rnd(3) === 0 ? p.signal(["lock", "unlock", "sleep", "wake", "displayOff", "displayOn"][rnd(6)], t) : p.sample(idle, t);
      if (!wasAway && p.away) aways++;
      if (r) { returns++; assert.ok(r.awayMs >= 0 && r.awaySince <= t, "the away lasted a time that makes sense"); assert.equal(lastReturn, false, "never twice in a row"); }
      lastReturn = r !== null;
      wasAway = p.away;
    }
    assert.ok(returns <= aways, `${returns} returns for ${aways} aways`);
  }
});

/** A Sidekick on a clock the test turns, with an idle reading it controls and counts. */
function world() {
  const w = { t: T0, idle: 0, calls: 0, fail: false, hold: null };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows",
    settings: () => ({ on: true, local: true, dismissals: {} }), saveSettings: () => {}, present: () => {}, updated: () => {}, timer: { set: () => 1, clear: () => {} },
    wait: () => new Promise(() => {}),
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true },
    idleSeconds: () => {
      w.calls++;
      if (w.hold) return w.hold;
      return w.fail ? Promise.reject(new Error("no")) : Promise.resolve(w.idle);
    },
  });
  const returns = [];
  sk.onReturn.push((r) => returns.push(r));
  return { w, sk, returns };
}
const hook = (name, extra = {}) => ({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
const settle = () => new Promise((r) => setTimeout(r, 0));

test("the idle time is read only while it can matter, at most every 5 s, never on a timer", async () => {
  const { w, sk } = world();
  await sk.sampleIdle();
  assert.equal(w.calls, 0, "no agent is running and the user is not away: nothing to look at");
  sk.hook(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  await settle();
  assert.equal(w.calls, 1, "a hook event with an agent running reads it");
  w.t += s(2);
  sk.hook(hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  await settle();
  assert.equal(w.calls, 1, "another within 5 s does not");
  w.t += SAMPLE_GAP_MS;
  sk.islandOpened();
  await settle();
  assert.equal(w.calls, 2, "the island opening reads it once the 5 s are over");
  assert.equal(SAMPLE_GAP_MS, 5000);
});

test("an unlock, a wake and the display coming on read it at once; a lock does not; a failing or odd reading is no reading", async () => {
  const { w, sk } = world();
  sk.hook(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  await settle();
  const base = w.calls;
  sk.presenceSignal("lock");
  await settle();
  assert.equal(w.calls, base, "a lock is not a moment to look");
  for (const word of ["unlock", "wake", "displayOn"]) {
    const before = w.calls;
    sk.presenceSignal(word);
    await settle();
    assert.equal(w.calls, before + 1, word);
  }
  w.fail = true;
  await sk.sampleIdle(true);
  w.fail = false;
  w.idle = Number.NaN;
  await sk.sampleIdle(true);
  w.idle = null;
  await sk.sampleIdle(true);
  assert.doesNotThrow(() => sk.presenceSignal(undefined));
});

test("a second reading is never started while one is on its way", async () => {
  const { w, sk } = world();
  sk.hook(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  await settle();
  let release;
  w.hold = new Promise((r) => { release = r; });
  w.calls = 0;
  const first = sk.sampleIdle(true);
  const second = sk.sampleIdle(true);
  await settle();
  assert.equal(w.calls, 1);
  release(0);
  await Promise.all([first, second]);
});

test("away by idle and back: the Sidekick tells its listeners once, with the real time away", async () => {
  const { w, sk, returns } = world();
  sk.hook(hook("PreToolUse", { tool_name: "Bash", tool_input: { command: "ls" } }));
  await settle();
  w.t += s(10); w.idle = 400;
  await sk.sampleIdle(true);
  assert.equal(sk.presence.away, true);
  w.t += s(120); w.idle = 6;
  await sk.sampleIdle(true);
  assert.equal(returns.length, 1);
  assert.equal(returns[0].awayMs, s(514), "the user was last at the keyboard 400 s before the first sample and came back 124 s after it");
  assert.equal(returns[0].awaySince, T0 + s(10) - s(400));
});

test("no timer, no interval and no thread: the Sidekick's presence never polls", () => {
  for (const f of ["controller.ts", "presence.ts", "ledger.ts"]) assert.doesNotMatch(source(`sidekick/${f}`), /setInterval|setTimeout|requestAnimationFrame/, f);
  const rust = ["sidekick.rs", "sidekick_presence.rs"].map((f) => fs.readFileSync(new URL(`../../src-tauri/src/${f}`, import.meta.url), "utf8")).join("\n");
  assert.doesNotMatch(rust, /thread::spawn|loop \{|interval|sleep\(/, "the Rust side only answers and forwards");
});

test("the wiring: the platform's news reaches the Sidekick, the island's opening is a moment to look, and Rust has one command and one callback for it", () => {
  assert.match(source("main.ts"), /onEvent<\{ signal: string \}>\("sidekick-away", \(\{ signal \}\) => Hub\.sk\?\.presenceSignal\(signal\)\);/);
  assert.match(source("island/island.ts"), /if \(mode !== "hidden"\) Hub\.sk\?\.islandOpened\(\);/);
  assert.match(source("core/bridge.ts"), /sidekickIdleSeconds: \(\) => call<number>\("sidekick_idle_seconds"\)/);
  assert.match(source("sidekick/appenv.ts"), /idleSeconds: async \(\) => \(await Bridge\.sidekickIdleSeconds\(\)\) \?\? null/);
  const lib = fs.readFileSync(new URL("../../src-tauri/src/lib.rs", import.meta.url), "utf8");
  assert.match(lib, /sidekick::sidekick_idle_seconds,/);
  assert.match(lib, /desktop::away_changed\(&away_handle, &away_gate, source, on\);\s*sidekick::away_changed\(&away_handle, source, on\);/);
  const win = fs.readFileSync(new URL("../../src-tauri/src/platform/windows.rs", import.meta.url), "utf8");
  assert.match(win, /GetLastInputInfo/);
  const lin = fs.readFileSync(new URL("../../src-tauri/src/platform/linux.rs", import.meta.url), "utf8");
  assert.match(lin, /org\.gnome\.Mutter\.IdleMonitor/);
});
