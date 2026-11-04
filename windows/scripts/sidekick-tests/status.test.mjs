import test from "node:test";
import assert from "node:assert/strict";
import { Sidekick } from "../../src/sidekick/controller.ts";
import { STATUS_CAPTION, STATUS_CHIP_TEXT, answerStatus, interleave } from "../../src/sidekick/statuschat.ts";
import { load, source } from "./util.mjs";

const T0 = 30_000_000;
function rig() {
  const w = { t: T0 };
  const sk = new Sidekick({
    now: () => w.t, platform: "windows", home: "C:\\Users\\me", idleSeconds: async () => null, settings: () => ({ on: true, local: true, dismissals: {} }), saveSettings: () => {},
    world: { ratelimit: () => false, card: () => null, ownCard: () => false, typing: () => false, onScreen: () => true }, present: () => {}, updated: () => {}, timer: { set: () => 1, clear: () => {} },
  });
  const hook = (name, extra = {}) => sk.hook({ hook_event_name: name, session_id: "S1", cwd: "C:\\work\\app", ...extra });
  return { w, sk, hook };
}

test("the contract's matcher decides what is the question: every message of the fixture matches or does not, and only the whole short message counts", () => {
  const { sk } = rig();
  for (const m of load("status-cases.json").matcher) assert.deepEqual(sk.matchStatus(m.text), { matched: m.matched, agentId: m.agentId }, JSON.stringify(m.text));
  assert.equal(sk.matchStatus(STATUS_CHIP_TEXT).matched, true, "the chip asks the question the matcher knows");
  for (const odd of ["Why is Claude doing that? What's Claude doing?", "what's claude doing in the file src/a.ts", "x".repeat(200), "", undefined, 7, null]) assert.equal(sk.matchStatus(odd).matched, false, String(odd));
});

test("nothing is running: the answer says so; an agent that is not running says so by name", () => {
  const { sk } = rig();
  assert.deepEqual(answerStatus("What's Claude doing?", sk, 0, 1), { id: 1, afterCount: 0, question: "What's Claude doing?", lines: ["Claude Code is not running right now."], facts: [] });
  assert.deepEqual(answerStatus("status", sk, 2, 2).lines, ["No agent is running right now."]);
  assert.deepEqual(answerStatus("what's gemini doing", sk, 0, 3).lines, ["Gemini CLI is not running right now."]);
});

test("a running agent is told in the recap's words, with counts and basenames and nothing else", () => {
  const { w, sk, hook } = rig();
  hook("PostToolUse", { tool_name: "Edit", tool_input: { file_path: "C:\\work\\app\\src\\SECRET-DIR\\main.ts", old_string: "SECRET-OLD", new_string: "SECRET-NEW" }, prompt: "SECRET-PROMPT" });
  w.t += 5000;
  hook("PostToolUse", { tool_name: "Bash", tool_input: { command: "echo SECRET-CMD" } });
  const a = answerStatus("what is claude doing right now?", sk, 4, 9);
  assert.equal(a.lines.length, 1);
  assert.match(a.lines[0], /^Claude Code in app has run 2 steps, edited main\.ts, and is still working\.$/);
  const text = JSON.stringify(a);
  for (const s of ["SECRET-DIR", "SECRET-OLD", "SECRET-NEW", "SECRET-PROMPT", "SECRET-CMD", "C:\\"]) assert.ok(!text.includes(s), s);
  assert.equal(a.afterCount, 4);
  assert.equal(a.facts.length, 1);
  assert.deepEqual(Object.keys(a.facts[0]).sort(), ["agent", "agentId", "approvals", "end", "errors", "files", "more", "project", "quietMinutes", "steps", "stepsAtLeast"]);
});

test("a message that is not the question is not answered here: it goes on to the chat, untouched", () => {
  const { sk } = rig();
  for (const text of ["Explain this stack trace", "What's the weather doing?", "status of my build pipeline please, in detail"]) assert.equal(answerStatus(text, sk, 0, 1), null, text);
});

test("the cards stand where they were asked: after the message they followed, a question and its answer together", () => {
  const msgs = ["m0", "m1", "m2"];
  const rows = interleave(msgs, [{ id: 1, afterCount: 0, question: "q", lines: ["a"] }, { id: 2, afterCount: 2, question: "q", lines: ["b"] }, { id: 3, afterCount: 3, question: "q", lines: ["c"] }]);
  assert.deepEqual(rows.map((r) => ("answer" in r ? `A${r.answer.id}` : r.message)), ["A1", "m0", "m1", "A2", "m2", "A3"]);
  assert.deepEqual(interleave(msgs, []).map((r) => r.message), msgs);
  assert.deepEqual(interleave([], [{ id: 1, afterCount: 5, question: "q", lines: [] }]).map((r) => r.answer.id), [1], "an answer after a conversation that was cleared is still shown");
  assert.equal(STATUS_CAPTION, "From NotchMeow, on this computer");
});

test("the chat answers before it chooses a model, keeps the card out of the conversation, and the chip asks the same question", () => {
  const chat = source("views/chat.ts");
  const submit = chat.slice(chat.indexOf("  async function submit() {"), chat.indexOf("  function continueOrRetry"));
  const at = (s) => { const i = submit.indexOf(s); assert.ok(i > 0, s); return i; };
  assert.ok(at("if (answerLocally(text)) return;") < at("cancelCountdown()"), "before a waiting retry is touched");
  assert.ok(at("if (answerLocally(text)) return;") < at("pendingAttachments()"), "before a dropped file is taken along");
  assert.ok(at("if (answerLocally(text)) return;") < at("featureFor("), "before a setting is chosen");
  assert.ok(at("if (answerLocally(text)) return;") < at("void ask("), "before any model is asked");
  assert.ok(at("if (answerLocally(text)) return;") < at("State.chatHistory.push"), "before the message joins the conversation");
  const local = chat.slice(chat.indexOf("  function answerLocally"), chat.indexOf("  function localCard"));
  assert.match(local, /State\.localAnswers\.push\(a\);/);
  assert.doesNotMatch(local, /chatHistory\.push|Bridge\.|ask\(/, "the local answer touches no conversation and no provider");
  assert.match(chat, /onclick: \(\) => void answerLocally\(STATUS_CHIP_TEXT\)/);
  assert.match(chat, /if \(Hub\.sk && Hub\.sk\.ledger\.live\.length > 0 && State\.chatHistory\.length === 0 && State\.localAnswers\.length === 0\) \{/, "the chip is there only while an agent is live");
  assert.match(chat, /Hub\.sk\?\.ledger\.live\.length \? "live" : "",/, "and the view redraws when that changes");
  assert.doesNotMatch(source("sidekick/statuschat.ts"), /Bridge|aiChat|fetch\(|import .*core\/bridge/, "the module has nothing that can talk to a model");
  assert.match(source("island/island.ts"), /State\.chatHistory = \[\];\s*State\.localAnswers = \[\];/, "a new conversation clears the cards");
});
