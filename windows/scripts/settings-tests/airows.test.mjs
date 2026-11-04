// The AI rows of Settings → AI and chat (airows.ts): which rows show, their words and chips, what Make main does, and which row is the chat's main choice.
// Port of NotchBuddy/Sources/App/SettingsAI.swift; the words are held to it by drift.test.mjs.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { rows, rowKey, title, line, chip, makeMain, helpLine, reasonLine, isMain, serverChip, getLink, PLAN_LINE } from "../../src/settings/airows.ts";
import { DEFAULT_AI } from "../../src/core/state.ts";
import { afterStopClaude, afterUseClaude } from "../../src/settings/airows.ts";

const I = {
  claudeState: "signedIn", claudeEnabled: true, claudeModel: "sonnet",
  keys: ["anthropic"], cloudModel: { anthropic: "claude-sonnet-5-5", openai: "gpt-6.1-sol" },
  servers: [
    { id: "ollama", name: "Ollama", network: false, models: ["qwen3.5:2b", "llama4"] },
    { id: "custom", name: "Studio PC", network: true, models: ["big"] },
    { id: "lmstudio", name: "LM Studio", network: false, models: [] },
  ],
  memory: { ollama: "llama4" },
};

test("rows: the plan rows, the three keys, then each server that has a model, in order", () => {
  assert.deepEqual(rows(I).map(rowKey), ["claudePlan", "openAIPlan", "key:anthropic", "key:google", "key:openai", "server:ollama", "server:custom"]);
  assert.ok(!rows(I).map((r) => title(r, I)).some((t) => /Google plan|ChatGPT/.test(t)));
});

test("titles: the plan rows, the key rows, and a server by its name", () => {
  assert.deepEqual([title({ kind: "claudePlan" }, I), title({ kind: "openAIPlan" }, I), title({ kind: "key", provider: "google" }, I)], ["Use my Claude plan", "Use my OpenAI plan", "Google AI API key"]);
  assert.equal(title({ kind: "server", id: "custom" }, I), "Studio PC");
});

test("lines: the plan words, the key words, and a server on this computer or on the network", () => {
  assert.equal(line({ kind: "openAIPlan" }, I), PLAN_LINE);
  assert.equal(line({ kind: "key", provider: "anthropic" }, I), "Your own key, saved on the Keys tab.");
  assert.deepEqual([line({ kind: "server", id: "custom" }, I), line({ kind: "server", id: "ollama" }, I)], ["A model server on your network.", "A model server on this computer."]);
});

test("chips: the plan states, the key states and the server counts", () => {
  assert.deepEqual(rows(I).slice(0, 6).map((r) => chip(r, I)), ["Ready", "Coming with the new chat", "Ready", "No key yet", "No key yet", "Running, 2 models"]);
  assert.equal(chip({ kind: "claudePlan" }, { ...I, claudeEnabled: false }), "Off");
  for (const [state, word] of [["signedOut", "Not signed in"], ["notInstalled", "Not installed"], ["tooOld", "Needs update"], ["unknown", "Not ready"], [null, "Not ready"]]) {
    assert.equal(chip({ kind: "claudePlan" }, { ...I, claudeState: state }), word);
  }
});

test("serverChip: the running counts and the other three states", () => {
  assert.deepEqual(
    [serverChip("running", 0), serverChip("running", 1), serverChip("running", 3), serverChip("off", 0), serverChip("notInstalled", 0), serverChip("outdated", 0)],
    ["Running, no models yet", "Running, 1 model", "Running, 3 models", "Server off", "Not installed", "Update needed"],
  );
});

test("makeMain: the Claude plan is set when signed in and enabled, else says why", () => {
  assert.deepEqual(makeMain({ kind: "claudePlan" }, I), { kind: "set", choice: { provider: "claudeCode", model: "sonnet" } });
  assert.deepEqual(makeMain({ kind: "claudePlan" }, { ...I, claudeEnabled: false }), { kind: "unavailable", reason: "Connect your Claude plan first." });
});

test("makeMain: the OpenAI plan says it is coming", () => {
  assert.deepEqual(makeMain({ kind: "openAIPlan" }, I), { kind: "unavailable", reason: "Coming with the new chat." });
});

test("makeMain: a key is set with its model, or says what is missing", () => {
  assert.deepEqual(makeMain({ kind: "key", provider: "anthropic" }, I), { kind: "set", choice: { provider: "anthropic", model: "claude-sonnet-5-5" } });
  assert.deepEqual(makeMain({ kind: "key", provider: "openai" }, I), { kind: "unavailable", reason: "Add a key on the Keys tab first." });
  assert.deepEqual(makeMain({ kind: "key", provider: "google" }, { ...I, keys: ["google"] }), { kind: "unavailable", reason: "Pick a model for it in the chat first." });
});

test("makeMain: a server with several models offers a menu with the remembered one first", () => {
  assert.deepEqual(makeMain({ kind: "server", id: "ollama" }, I), { kind: "menu", choices: [{ provider: "ollama", model: "llama4" }, { provider: "ollama", model: "qwen3.5:2b" }] });
  assert.deepEqual(makeMain({ kind: "server", id: "custom" }, I), { kind: "set", choice: { provider: "custom", model: "big" } });
  assert.deepEqual(makeMain({ kind: "server", id: "lmstudio" }, I), { kind: "unavailable", reason: "Start the server and load a model first." });
});

test("helpLine and reasonLine: a key with no key has neither; a reason is shown unless the chip already says it", () => {
  assert.equal(helpLine({ kind: "key", provider: "openai" }, I), null);
  assert.equal(reasonLine({ kind: "key", provider: "openai" }, I), null);
  assert.equal(reasonLine({ kind: "openAIPlan" }, I), null);
  assert.equal(reasonLine({ kind: "claudePlan" }, { ...I, claudeEnabled: false }), "Connect your Claude plan first.");
});

test("isMain: Auto has no main row; each row matches its own provider only", () => {
  assert.ok(rows(I).every((r) => !isMain(r, "auto")));
  assert.deepEqual(rows(I).filter((r) => isMain(r, { provider: "ollama", model: "qwen3.5:2b" })).map(rowKey), ["server:ollama"]);
  assert.deepEqual(rows(I).filter((r) => isMain(r, { provider: "anthropic", model: "claude-opus-5-5" })).map(rowKey), ["key:anthropic"]);
  assert.deepEqual(rows(I).filter((r) => isMain(r, { provider: "claudeCode", model: "opus" })).map(rowKey), ["claudePlan"]);
  assert.deepEqual(rows(I).filter((r) => isMain(r, { provider: "openai", model: "gpt-6.1-sol" })).map(rowKey), ["key:openai"]);
});

test("getLink: the four local servers, and none for a cloud provider", () => {
  assert.deepEqual([getLink("ollama"), getLink("lmstudio"), getLink("jan"), getLink("llamacpp")], ["https://ollama.com/download", "https://lmstudio.ai", "https://jan.ai", "https://github.com/ggml-org/llama.cpp"]);
  assert.equal(getLink("anthropic"), null);
  assert.equal(getLink("constructor"), null);
});

test("stop using Claude: Claude off, the preference moves to Anthropic, a Claude chat goes back to Auto, other choices stay", () => {
  const inUse = { ...DEFAULT_AI, claudeCodeEnabled: true, preferredCloud: "claudeCode", chat: { provider: "claudeCode", model: "sonnet" } };
  const off = afterStopClaude(inUse);
  assert.equal(off.claudeCodeEnabled, false);
  assert.equal(off.preferredCloud, "anthropic");
  assert.equal(off.chat, "auto");
  assert.equal(afterStopClaude({ ...inUse, preferredCloud: "openai" }).preferredCloud, "openai", "OpenAI stays first");
  assert.deepEqual(afterStopClaude({ ...inUse, chat: { provider: "openai", model: "gpt" } }).chat, { provider: "openai", model: "gpt" }, "a non-Claude chat is kept");
  assert.equal(afterStopClaude({ ...inUse, chat: "auto" }).chat, "auto", "Auto stays Auto");
});

test("use my Claude plan: enabled, Claude first, and the chat back on Auto", () => {
  const used = afterUseClaude({ ...DEFAULT_AI, claudeCodeEnabled: false, preferredCloud: "anthropic", chat: { provider: "openai", model: "gpt" } });
  assert.equal(used.claudeCodeEnabled, true);
  assert.equal(used.preferredCloud, "claudeCode");
  assert.equal(used.chat, "auto");
});

test("isMain: a server whose id is reserved (claudeCode, anthropic, google, openai) is never the main row, even when the chat names it", () => {
  for (const id of ["claudeCode", "anthropic", "google", "openai"]) {
    assert.equal(isMain({ kind: "server", id }, { provider: id, model: "m" }), false, `${id} is reserved`);
  }
  assert.equal(isMain({ kind: "server", id: "ollama" }, { provider: "ollama", model: "m" }), true, "an ordinary id still matches");
});

test("aiInput: every server the store reports goes into the rows, whatever its status (the chip says running; the status is not read here)", () => {
  // aiInput needs the DOM (ai.ts imports the views), so this reads its body: the servers are mapped in one step, with no status test.
  const ai = fs.readFileSync(new URL("../../src/settings/ai.ts", import.meta.url), "utf8");
  const start = ai.indexOf("export function aiInput(");
  assert.ok(start >= 0, "aiInput exists");
  const body = ai.slice(start, ai.indexOf("\n}\n", start));
  assert.ok(body.includes("servers: ctx.ai.servers.map("), "the servers are mapped from the cache");
  // The status is carried to the signature, never tested here: no filter or comparison on it.
  assert.doesNotMatch(body, /filter\([^)]*status|status\s*(===|!==)|\.status\s*(===|!==)/, "no status test in aiInput");
});

test("resolveSignature: the same settings, keys and servers give the same signature; a changed choice, a saved key or a server changes it", async () => {
  const { resolveSignature } = await import("../../src/settings/airows.ts");
  const ai = { ...DEFAULT_AI };
  const base = resolveSignature(ai, I);
  assert.equal(resolveSignature({ ...DEFAULT_AI }, { ...I }), base, "an echo of nothing new keeps it");
  assert.notEqual(resolveSignature({ ...ai, chat: { provider: "openai", model: "gpt-6.1-sol" } }, I), base, "a changed choice");
  assert.notEqual(resolveSignature(ai, { ...I, keys: [...I.keys, "openai"] }), base, "a key saved");
  assert.notEqual(resolveSignature(ai, { ...I, unreadable: ["openai"] }), base, "a key the store cannot read");
  assert.notEqual(resolveSignature(ai, { ...I, servers: [] }), base, "a server gone");
  assert.equal(resolveSignature(ai, { ...I, unreadable: undefined }), base, "no unreadable list is the same as none");
});

test("resolveSignature: a provider's model list that arrives or changes changes it, because Auto's default reads the list (Google has no catalog default)", async () => {
  const { resolveSignature } = await import("../../src/settings/airows.ts");
  const ai = { ...DEFAULT_AI };
  const none = resolveSignature(ai, { ...I, cloudIds: {} });
  const one = resolveSignature(ai, { ...I, cloudIds: { google: ["gemini-2.5-pro"] } });
  assert.notEqual(one, none, "a list arriving");
  assert.notEqual(resolveSignature(ai, { ...I, cloudIds: { google: ["gemini-2.5-flash"] } }), one, "a list changing its first id");
  assert.notEqual(resolveSignature(ai, { ...I, cloudIds: { google: ["gemini-2.5-pro", "gemini-2.5-flash"] } }), one, "a list growing");
  assert.equal(resolveSignature(ai, { ...I, cloudIds: { google: ["gemini-2.5-pro"] } }), one, "the same list is the same signature");
});

test("resolveSignature: a server's status changes it, because routing takes only Running servers", async () => {
  const { resolveSignature } = await import("../../src/settings/airows.ts");
  const ai = { ...DEFAULT_AI };
  const running = { ...I, servers: [{ id: "ollama", name: "Ollama", network: false, models: ["llama4"], status: "running" }] };
  const base = resolveSignature(ai, running);
  assert.equal(resolveSignature(ai, JSON.parse(JSON.stringify(running))), base, "an identical input is the same");
  assert.notEqual(resolveSignature(ai, { ...I, servers: [{ ...running.servers[0], status: "off" }] }), base, "a server turned off");
});
