// Add server and Remove server on Your AI -> Local models, run for real: the two functions are cut out of ai.ts (they close over the card's `msg` and `addOpen`, which the harness
// supplies) and played against a fake saver and credential store. What is held: a settings save that is refused keeps the form, the typed address and key, and leaves the
// credential store as it was (Task 1 of the final-review fix wave; the review's I1). The wiring around them is pinned as text in pages.test.mjs.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DraftBook } from "../../src/settings/drafts.ts";
import { sliceBetween } from "./slice.mjs";

const ai = fs.readFileSync(new URL("../../src/settings/ai.ts", import.meta.url), "utf8");
const CUSTOM_URL = "custom-server-url";
const CUSTOM_KEY = "custom-server-key.default";

/** Builds the page function `name` from ai.ts's text, with a fake context. `saveAnswers` is what ctx.save resolves; `clearThrows` makes secretClear refuse. */
function harness(name, { saveAnswers = true, clearThrows = false, customServer = null } = {}) {
  const src = sliceBetween(ai, `  async function ${name}(`, "\n  }\n").replace("): Promise<void> {", ") {");
  const calls = [];
  const drafts = new DraftBook({}, []);
  const ctx = {
    drafts,
    settings: () => ({ ai: { customServer } }),
    save: async (next) => {
      calls.push(`save ${next.ai.customServer}`);
      return saveAnswers;
    },
    backend: {
      secretSet: async (key) => void calls.push(`set ${key}`),
      secretClear: async (key) => {
        calls.push(`clear ${key}`);
        if (clearThrows) throw new Error("the store refused");
      },
    },
  };
  const factory = new Function(
    "ctx", "paint", "refreshServers", "isHttpUrl", "originOf", "CUSTOM_URL", "CUSTOM_KEY",
    `let msg = null; let addOpen = true; ${src}\nreturn { run: ${name}, state: () => ({ msg, addOpen }) };`,
  );
  const page = factory(ctx, () => calls.push("paint"), async () => void calls.push("refresh"), (u) => /^https?:\/\//.test(u), (u) => new URL(u).origin, CUSTOM_URL, CUSTOM_KEY);
  return { ...page, calls, drafts };
}

test("Add server with a key: a refused settings save keeps the form and the typed text, takes the key back, and does not refresh", async () => {
  const t = harness("addServer", { saveAnswers: false });
  t.drafts.edit(CUSTOM_URL, "http://studio-pc:11434");
  t.drafts.edit(CUSTOM_KEY, "sk-typed");
  await t.run();
  assert.deepEqual(t.calls, ["set custom-server-key.default", "save http://studio-pc:11434", "clear custom-server-key.default"], "the key is written, the save is refused, the key is taken back");
  assert.equal(t.drafts.text(CUSTOM_URL), "http://studio-pc:11434", "the typed address stays");
  assert.equal(t.drafts.text(CUSTOM_KEY), "sk-typed", "the typed key stays");
  assert.equal(t.state().addOpen, true, "the form stays open");
  assert.equal(t.state().msg, null, "the saver's own note says what failed");
  assert.ok(!t.calls.includes("refresh"));
});

test("Add server with a key: a refused save whose key cannot be taken back says so", async () => {
  const t = harness("addServer", { saveAnswers: false, clearThrows: true });
  t.drafts.edit(CUSTOM_URL, "http://studio-pc:11434");
  t.drafts.edit(CUSTOM_KEY, "sk-typed");
  await t.run();
  assert.equal(t.state().msg.kind, "err");
  assert.equal(t.state().msg.text, "Couldn't remove the server's key from the credential store.");
  assert.equal(t.state().addOpen, true);
});

test("Add server: a save that works closes the form, clears the address, marks the key stored and looks the servers up", async () => {
  const t = harness("addServer", { saveAnswers: true });
  t.drafts.edit(CUSTOM_URL, "http://studio-pc:11434");
  t.drafts.edit(CUSTOM_KEY, "sk-typed");
  await t.run();
  assert.deepEqual(t.calls, ["set custom-server-key.default", "save http://studio-pc:11434", "refresh"]);
  assert.equal(t.drafts.text(CUSTOM_URL), "");
  assert.equal(t.drafts.isSaved(CUSTOM_KEY), true);
  assert.equal(t.state().addOpen, false);
});

test("Add server with no key: a refused save leaves the form as it was (the stale key was already cleared, which is never the wrong side to fail on)", async () => {
  const t = harness("addServer", { saveAnswers: false });
  t.drafts.edit(CUSTOM_URL, "http://studio-pc:11434");
  await t.run();
  assert.deepEqual(t.calls, ["clear custom-server-key.default", "save http://studio-pc:11434"]);
  assert.equal(t.drafts.text(CUSTOM_URL), "http://studio-pc:11434");
  assert.equal(t.state().addOpen, true);
});

test("Remove server: a refused save keeps the server and its key", async () => {
  const t = harness("removeServer", { saveAnswers: false, customServer: "http://studio-pc:11434" });
  await t.run();
  assert.deepEqual(t.calls, ["save null"], "the key is not touched");
});

test("Remove server: the key is cleared only after the save works", async () => {
  const t = harness("removeServer", { saveAnswers: true, customServer: "http://studio-pc:11434" });
  await t.run();
  assert.deepEqual(t.calls, ["save null", "clear custom-server-key.default", "refresh"]);
  assert.equal(t.drafts.isSaved(CUSTOM_KEY), false);
  assert.equal(t.state().msg, null);
});

test("Remove server: a key that cannot be cleared after the server went is said, and the list is still refreshed", async () => {
  const t = harness("removeServer", { saveAnswers: true, clearThrows: true, customServer: "http://studio-pc:11434" });
  await t.run();
  assert.deepEqual(t.calls, ["save null", "clear custom-server-key.default", "refresh"]);
  assert.equal(t.state().msg.text, "Couldn't remove the server's key from the credential store.");
});

// S1: a key left behind (a Remove server whose clear failed) is never inherited by the next server added without a key.
test("Add server with no key and none configured: a stale stored key is cleared before the server is saved", async () => {
  const t = harness("addServer", { saveAnswers: true, customServer: null });
  t.drafts.edit(CUSTOM_URL, "http://studio-pc:11434");
  await t.run();
  assert.deepEqual(t.calls, ["clear custom-server-key.default", "save http://studio-pc:11434", "refresh"]);
});

test("Add server with no key: a clear that fails refuses the add and keeps the form", async () => {
  const t = harness("addServer", { saveAnswers: true, clearThrows: true, customServer: null });
  t.drafts.edit(CUSTOM_URL, "http://studio-pc:11434");
  await t.run();
  assert.deepEqual(t.calls, ["clear custom-server-key.default", "paint"], "the server is not saved");
  assert.equal(t.state().msg.text, "Couldn't remove the old server's key from the credential store.");
  assert.equal(t.drafts.text(CUSTOM_URL), "http://studio-pc:11434");
  assert.equal(t.state().addOpen, true);
});

test("Add server with no key: a store that cannot be read refuses the add before anything is cleared or saved", async () => {
  const t = harness("addServer", { saveAnswers: true, customServer: null });
  t.drafts.setPresence(CUSTOM_KEY, "unreadable");
  t.drafts.edit(CUSTOM_URL, "http://studio-pc:11434");
  await t.run();
  assert.deepEqual(t.calls, ["paint"]);
  assert.equal(t.state().msg.kind, "err");
});

test("Add server with no key: the same server again keeps its key, a different one clears it first", async () => {
  const same = harness("addServer", { saveAnswers: true, customServer: "http://studio-pc:11434" });
  same.drafts.edit(CUSTOM_URL, "http://studio-pc:11434");
  await same.run();
  assert.deepEqual(same.calls, ["save http://studio-pc:11434", "refresh"]);
  const other = harness("addServer", { saveAnswers: true, customServer: "http://studio-pc:11434" });
  other.drafts.edit(CUSTOM_URL, "http://other-pc:11434");
  await other.run();
  assert.deepEqual(other.calls, ["clear custom-server-key.default", "save http://other-pc:11434", "refresh"]);
});
