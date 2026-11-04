import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { FACT_KEYS, allowedFacts, nicerLine, nicerLines, voiceRequest } from "../../src/sidekick/voice.ts";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { cleanSidekickSettings } from "../../src/sidekick/core.ts";
import { source } from "./util.mjs";

const T0 = 40_000_000;
const MIN = 60_000;
const SECRETS = ["SECRET-CMD", "SECRET-PATH", "SECRET-PROMPT", "SECRET-WORDS", "SECRET-BODY"];
const fact = { agent: "Claude Code", agentId: "integration_claude", project: "app", steps: 12, stepsAtLeast: false, files: ["a.ts", "b.ts"], more: 0, errors: 1, approvals: 2, end: "finished", quietMinutes: 0 };

test("a model is given only the allowed fields of a fact, cut to a template's sizes; every other field is dropped", () => {
  const hostile = { ...fact, command: SECRETS[0], path: `C:\\${SECRETS[1]}`, prompt: SECRETS[2], last_assistant_message: SECRETS[3], content: SECRETS[4], files: ["a.ts", "b.ts", "c.ts", "d.ts", `C:\\${SECRETS[1]}\\e.ts`, { evil: SECRETS[0] }], project: "p".repeat(500), nested: { command: SECRETS[0] } };
  const got = allowedFacts(hostile);
  assert.deepEqual(Object.keys(got).filter((k) => !FACT_KEYS.includes(k)), []);
  assert.deepEqual(got.files, ["a.ts", "b.ts", "c.ts"], "three names at most, none that is not text or a number");
  assert.equal(got.project.length, 60);
  const text = JSON.stringify(voiceRequest("Claude Code ran 12 steps.", hostile));
  for (const s of SECRETS) assert.ok(!text.includes(s), s);
  for (const odd of [null, undefined, 7, "x", [], [fact]]) assert.deepEqual(allowedFacts(odd), {}, String(odd));
  assert.deepEqual(allowedFacts({ steps: Number.NaN, errors: Number.POSITIVE_INFINITY, end: {}, files: [Number.NaN, null, {}] }), { files: [] }, "a number that is not a number, and a thing that is not text, are no facts");
});

test("a request is short: a normal recap line is well under 800 characters, and the largest one a template can make is under the 1200 Rust allows", () => {
  const normal = voiceRequest("While you were away, Claude Code in app ran 12 steps (1 error, 2 approvals asked), edited a.ts, b.ts and c.ts, and finished.", fact);
  assert.ok(normal.system.length + normal.prompt.length < 800, `${normal.system.length + normal.prompt.length} characters`);
  const big = { ...fact, project: "p".repeat(60), files: ["f".repeat(60), "g".repeat(60), "h".repeat(60)], more: 40 };
  const r = voiceRequest("While you were away, Claude Code in " + "p".repeat(60) + " ran 40 or more steps (3 errors, 12 approvals asked), edited " + "f".repeat(60) + ", " + "g".repeat(60) + " and 41 more, and has been quiet for 30 minutes.", big);
  assert.ok(r.system.length + r.prompt.length < 1200, `${r.system.length + r.prompt.length} characters`);
});

test("a nicer sentence is taken only if the contract's check accepts it; every other answer leaves the template", async () => {
  const template = "Claude Code ran 12 steps in app.";
  const says = (reply) => async () => reply;
  assert.equal(await nicerLine(says("Claude Code worked through 12 steps in app."), template, fact), "Claude Code worked through 12 steps in app.");
  assert.equal(await nicerLine(says("  Claude Code ran 12 steps in app.\n"), template, fact), null, "the same sentence is no change");
  for (const bad of ["Claude Code ran 13 steps in app.", "Claude Code ran 12 steps: see https://example.com", "It ran 12 steps in app.", "Claude Code ran 12 steps in C:\\work\\app.", "Claude Code ran 12 steps.\nAnd more.", "Claude Code `ran` 12 steps.", "**Claude Code** ran 12 steps.", "", "   ", "x".repeat(300) + " Claude Code 12"]) assert.equal(await nicerLine(says(bad), template, fact), null, JSON.stringify(bad));
  for (const reply of [null, undefined, 7, {}, ["Claude Code ran 12 steps."]]) assert.equal(await nicerLine(says(reply), template, fact), null, String(reply));
  assert.equal(await nicerLine(async () => { throw new Error("no model"); }, template, fact), null, "an error is no sentence");
  assert.equal(await nicerLine(() => { throw new Error("sync"); }, template, fact), null);
});

test("lines are worded one by one from their own facts; a line with no fact (\"+2 more\") stays; null when nothing changed", async () => {
  const asked = [];
  const oneshot = async (system, prompt) => { asked.push(prompt); return /Gemini/.test(prompt) ? "Gemini CLI did 3 steps in app." : null; };
  const f2 = { ...fact, agent: "Gemini CLI", agentId: "agent_gemini", steps: 3 };
  const lines = ["While you were away, Claude Code ran 12 steps.", "While you were away, Gemini CLI ran 3 steps.", "+2 more"];
  assert.deepEqual(await nicerLines(oneshot, lines, [fact, f2]), [lines[0], "Gemini CLI did 3 steps in app.", "+2 more"]);
  assert.equal(asked.length, 2, "two lines have facts, the third has none");
  assert.equal(await nicerLines(async () => null, lines, [fact, f2]), null);
});

/** A Sidekick with a fake model, a clock and a note on screen. */
function rig(settings = {}, reply = async (system, prompt) => "Claude Code has run 4 steps and finished in app.") {
  const w = { t: T0, asked: [], presented: [], updated: [], hovering: false, onScreen: true, settings: cleanSidekickSettings(settings) };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", home: "C:\\Users\\me", idleSeconds: async () => null,
    settings: () => w.settings, saveSettings: (s) => { w.settings = s; },
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => w.onScreen },
    present: (n) => w.presented.push(n), updated: (n) => w.updated.push(n),
    oneshot: async (system, prompt) => { w.asked.push({ system, prompt }); return reply(system, prompt); }, hovering: () => w.hovering,
    timer: { set: () => 1, clear: () => {} },
  });
  const hook = (name, extra = {}) => sk.hook({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
  return { w, sk, hook };
}
const settle = () => new Promise((r) => setTimeout(r, 0));
const recapOnReturn = async (r) => {
  r.sk.presenceSignal("lock");
  r.w.t += 5000;
  for (let i = 0; i < 4; i++) { r.hook("PostToolUse", { tool_name: "Bash", tool_input: { command: `SECRET-CMD ${i}` }, prompt: "SECRET-PROMPT" }); r.w.t += 1000; }
  r.hook("Stop", { last_assistant_message: "SECRET-WORDS" });
  r.w.t += 5 * MIN;
  r.sk.presenceSignal("unlock");
  await settle();
};

test("a note is shown with its template first; a nicer sentence from a local model swaps in once; the model saw only the facts", async () => {
  const r = rig({}, async () => "Claude Code finished 4 steps in app and stopped.");
  await recapOnReturn(r);
  assert.equal(r.w.presented.length, 1);
  assert.match(r.w.presented[0].lines[0], /^While you were away, Claude Code in app ran 4 steps and finished\.$/, "the template was shown first");
  assert.deepEqual(r.w.updated.map((n) => n.lines[0]), ["Claude Code finished 4 steps in app and stopped."]);
  assert.equal(r.w.asked.length, 1);
  const seen = JSON.stringify(r.w.asked);
  for (const s of SECRETS) assert.ok(!seen.includes(s), `the model was shown ${s}`);
  assert.match(r.w.asked[0].prompt, /Facts: \{"agent":"Claude Code","project":"app","steps":4/);
  assert.equal(r.sk.notes.current.lines[0], "Claude Code finished 4 steps in app and stopped.");
  await settle();
  assert.equal(r.w.updated.length, 1, "swapped once, and nothing changes after that");
});

test("no swap when the switch is off, when the pointer is over the note, when the note is gone or when the sentence is not accepted; and no request at all when it is off", async () => {
  const off = rig({ local: false });
  await recapOnReturn(off);
  assert.equal(off.w.asked.length, 0, "Nicer wording off: the model is never asked");
  assert.equal(off.w.updated.length, 0);
  const over = rig();
  over.w.hovering = true;
  await recapOnReturn(over);
  assert.equal(over.w.asked.length, 1);
  assert.equal(over.w.updated.length, 0, "the pointer is over the note: it does not change under it");
  const gone = rig({}, async () => { gone.w.onScreen = false; gone.sk.stateChanged(); return "Claude Code finished 4 steps in app and stopped."; });
  await recapOnReturn(gone);
  assert.equal(gone.w.updated.length, 0, "the note was folded away before the sentence came");
  const bad = rig({}, async () => "Claude Code finished 9 steps in app.");
  await recapOnReturn(bad);
  assert.equal(bad.w.updated.length, 0, "a number that is not in the facts");
  const slow = rig({}, async () => { throw new Error("timeout"); });
  await recapOnReturn(slow);
  assert.equal(slow.w.presented.length, 1, "a model that fails leaves the template");
});

test("the permission line is never reworded, and the chat's status card is worded by the same rules", async () => {
  assert.doesNotMatch(source("island/hooks.ts"), /voice|oneshot|polish/i);
  assert.doesNotMatch(source("sidekick/explain.ts"), /voice|oneshot|polish/i);
  const r = rig({}, async () => "Claude Code has done 4 steps in app and is still working.");
  r.hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "ls" } });
  r.hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "ls" } });
  const a = r.sk.status(null);
  const next = await r.sk.polishLines(a.lines, a.facts);
  assert.equal(next, null, "2 steps in the facts, 4 in the sentence: not accepted");
  const ok = rig({}, async () => "Claude Code has taken 2 steps in app and is still working.");
  ok.hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "ls" } });
  ok.hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "ls" } });
  const b = ok.sk.status(null);
  assert.deepEqual(await ok.sk.polishLines(b.lines, b.facts), ["Claude Code has taken 2 steps in app and is still working."]);
  const off = rig({ local: false });
  assert.equal(await off.sk.polishLines(["x"], [fact]), null);
});

test("the wiring: the one-shot goes through Rust's command, the Settings line asks for the model's name, and the Rust side only ever asks a model on this computer", () => {
  assert.match(source("core/bridge.ts"), /aiOneshot: \(system: string, prompt: string\) => call<string>\("ai_oneshot", \{ system, prompt \}\)/);
  assert.match(source("core/bridge.ts"), /aiLocalModel: \(\) => call<string>\("ai_local_model"\)/);
  assert.match(source("sidekick/appenv.ts"), /oneshot: async \(system, prompt\) => \(await Bridge\.aiOneshot\(system, prompt\)\) \?\? null/);
  assert.match(source("settings/app.ts"), /found: async \(\) => \(await ctx\.backend\.aiLocalModel\(\)\) \?\? null,/);
  const mod = fs.readFileSync(new URL("../../src-tauri/src/ai/mod.rs", import.meta.url), "utf8");
  const one = mod.slice(mod.indexOf("async fn local_target"), mod.indexOf("/// One chat turn, streamed")).split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");
  assert.match(one, /oneshot::pick\(&ready, env\.settings\.last_used_local\.as_ref\(\)\)\?/);
  assert.match(one, /s\.placement == Placement::Local/, "the server is local too, not only the model");
  assert.doesNotMatch(one, /turn_env|read_keys|keychain|secrets::|choice\(|route\(|Auto/, "no key is read and the chat's own choice is not consulted");
  assert.doesNotMatch(one, /log::line|eprintln|println/, "nothing is logged");
  assert.match(one, /key: None,/);
  const lib = fs.readFileSync(new URL("../../src-tauri/src/lib.rs", import.meta.url), "utf8");
  assert.match(lib, /ai::ai_oneshot,\s*ai::ai_local_model,/);
  assert.match(fs.readFileSync(new URL("../../src-tauri/src/ai/session.rs", import.meta.url), "utf8"), /pub\(crate\) async fn rediscover/);
});
