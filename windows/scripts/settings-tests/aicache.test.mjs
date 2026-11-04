// The AI cache (aicache.ts): the one refresh of the AI section when its window opens, moved from main.ts's aiSection. A fake backend and a fake clock.
import test from "node:test";
import assert from "node:assert/strict";
import { AiCache, MODEL_LIST_MAX_AGE_MS, REFRESH_GAP_MS, discoveryMsg } from "../../src/settings/aicache.ts";

const MINUTE = 60 * 1000;
const PROVIDERS = [{ id: "anthropic", key: "anthropic-api-key" }, { id: "openai", key: "openai-api-key" }];
const present = (key) => key === "anthropic-api-key";

function fakeBackend({ failing = new Set() } = {}) {
  const calls = { discover: 0, claude: 0, models: [] };
  return {
    calls,
    async aiDiscover() { calls.discover++; await Promise.resolve(); return []; },
    async claudeStatus() { calls.claude++; return undefined; },
    async aiListModels(provider) {
      calls.models.push(provider);
      if (failing.has(provider)) throw new Error("Error: key was rejected.");
      return [{ id: `${provider}-model`, displayName: "Model", contextTokens: null, capabilities: { tools: true, vision: false, json: false } }];
    },
  };
}

function clock(start = 1_000_000) {
  let t = start;
  return { now: () => t, advance: (ms) => { t += ms; } };
}

test("refreshOnOpen: two calls started together run once; the second returns false", async () => {
  const backend = fakeBackend();
  const cache = new AiCache(backend, PROVIDERS, present, clock().now);
  const [a, b] = await Promise.all([cache.refreshOnOpen(), cache.refreshOnOpen()]);
  assert.deepEqual([a, b], [true, false]);
  assert.equal(backend.calls.discover, 1);
});

test("refreshOnOpen: skipped until 1000 ms after the last one ended", async () => {
  const c = clock();
  const backend = fakeBackend();
  const cache = new AiCache(backend, PROVIDERS, present, c.now);
  assert.equal(await cache.refreshOnOpen(), true);
  c.advance(500);
  assert.equal(await cache.refreshOnOpen(), false);
  c.advance(501);
  assert.equal(await cache.refreshOnOpen(), true);
  assert.equal(backend.calls.discover, 2);
});

test("refreshOnOpen: loads only the providers whose key is saved", async () => {
  const backend = fakeBackend();
  const cache = new AiCache(backend, PROVIDERS, present, clock().now);
  await cache.refreshOnOpen();
  assert.deepEqual(backend.calls.models, ["anthropic"]);
  assert.equal(cache.models.openai, undefined);
  assert.equal(cache.models.anthropic[0].id, "anthropic-model");
});

test("refreshOnOpen: a list is kept for 10 minutes, then fetched again", async () => {
  assert.equal(MODEL_LIST_MAX_AGE_MS, 10 * MINUTE);
  const c = clock();
  const backend = fakeBackend();
  const cache = new AiCache(backend, PROVIDERS, present, c.now);
  await cache.refreshOnOpen();
  c.advance(9 * MINUTE);
  await cache.refreshOnOpen();
  assert.equal(backend.calls.models.length, 1);
  c.advance(10 * MINUTE + 1 - 9 * MINUTE);
  await cache.refreshOnOpen();
  assert.equal(backend.calls.models.length, 2);
});

test("loadCloud: a failed check returns false and leaves no list", async () => {
  const cache = new AiCache(fakeBackend({ failing: new Set(["anthropic"]) }), PROVIDERS, present, clock().now);
  assert.equal(await cache.loadCloud("anthropic"), false);
  assert.equal(cache.models.anthropic, undefined);
  assert.equal(cache.works.anthropic.ok, false);
});

test("forget: removes the list and the check's result", async () => {
  const cache = new AiCache(fakeBackend(), PROVIDERS, present, clock().now);
  assert.equal(await cache.loadCloud("anthropic"), true);
  assert.equal(cache.works.anthropic.ok, true);
  cache.forget("anthropic");
  assert.equal(cache.models.anthropic, undefined);
  assert.equal(cache.works.anthropic, undefined);
});

test("setServers: an equal list changes nothing; a different one is kept", () => {
  const cache = new AiCache(fakeBackend(), PROVIDERS, present, clock().now);
  const one = [{ provider: "ollama", name: "Ollama", status: "running", models: [] }];
  assert.equal(cache.setServers(one), true);
  assert.equal(cache.setServers(JSON.parse(JSON.stringify(one))), false);
  assert.equal(cache.setServers([{ ...one[0], status: "off" }]), true);
  assert.equal(cache.servers[0].status, "off");
});

test("refreshOnOpen: a Claude status read that rejects still marks the read done, and the rest of the refresh runs (discovery and the cloud lists)", async () => {
  const backend = fakeBackend();
  backend.claudeStatus = async () => { backend.calls.claude++; throw new Error("claude_status failed"); };
  const cache = new AiCache(backend, PROVIDERS, present, clock().now);
  assert.equal(await cache.refreshOnOpen(), true, "the refresh resolves and reports that it ran");
  assert.equal(cache.claudeRead, true, "the read is marked done, so the row says it could not check");
  assert.equal(cache.claude, null, "no status is held");
  assert.equal(backend.calls.discover, 1, "discovery still runs");
  assert.deepEqual(backend.calls.models, ["anthropic"], "the saved provider's list still loads");
  assert.ok(cache.models.anthropic?.length > 0);
});

/** A promise the test settles by hand, so a list can be in flight while the test does something else. */
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

test("forget while a list is in flight: the late answer does not bring the removed key's list back", async () => {
  const backend = fakeBackend();
  const late = deferred();
  backend.aiListModels = async () => late.promise;
  const cache = new AiCache(backend, PROVIDERS, present, clock().now);
  const inFlight = cache.loadCloud("anthropic");
  cache.forget("anthropic");
  late.resolve([{ id: "stale-model", displayName: "Stale", contextTokens: null, capabilities: { tools: true, vision: false, json: false } }]);
  assert.equal(await inFlight, false, "the superseded load does not land");
  assert.equal(cache.models.anthropic, undefined, "no list for the removed key");
  assert.equal(cache.works.anthropic, undefined, "no check result for the removed key");
});

test("forget while a failing check is in flight: its failure does not come back either", async () => {
  const backend = fakeBackend();
  const late = deferred();
  backend.aiListModels = async () => late.promise;
  const cache = new AiCache(backend, PROVIDERS, present, clock().now);
  const inFlight = cache.loadCloud("anthropic");
  cache.forget("anthropic");
  late.reject(new Error("Error: key was rejected."));
  assert.equal(await inFlight, false);
  assert.equal(cache.works.anthropic, undefined);
});

test("a load started after forget lands as usual, and the older load in flight does not replace it", async () => {
  const backend = fakeBackend();
  const old = deferred();
  backend.aiListModels = async () => old.promise;
  const cache = new AiCache(backend, PROVIDERS, present, clock().now);
  const first = cache.loadCloud("anthropic");
  cache.forget("anthropic");
  backend.aiListModels = async () => [{ id: "fresh", displayName: "Fresh", contextTokens: null, capabilities: { tools: true, vision: false, json: false } }];
  assert.equal(await cache.loadCloud("anthropic"), true);
  old.resolve([]);
  assert.equal(await first, false);
  assert.equal(cache.models.anthropic[0].id, "fresh", "the newer load's list is what is held");
});

test("refreshOnOpen: a discovery that rejects keeps the server list held, and the cloud lists still load", async () => {
  const backend = fakeBackend();
  const c = clock();
  const one = [{ provider: "ollama", name: "Ollama", status: "running", models: [] }];
  backend.aiDiscover = async () => one;
  const cache = new AiCache(backend, PROVIDERS, present, c.now);
  await cache.refreshOnOpen();
  backend.aiDiscover = async () => { throw new Error("discover failed"); };
  c.advance(REFRESH_GAP_MS + 1);
  assert.equal(await cache.refreshOnOpen(), true, "the refresh resolves");
  assert.deepEqual(cache.servers, one, "a rejected read wipes nothing");
  assert.ok(cache.models.anthropic?.length > 0, "the saved provider's list still loads (stale check reruns only after 10 min, so the first list stays)");
});

test("refreshOnOpen: a discovery that answers undefined keeps the server list held before it", async () => {
  const backend = fakeBackend();
  const c = clock();
  const one = [{ provider: "ollama", name: "Ollama", status: "running", models: [] }];
  backend.aiDiscover = async () => one;
  const cache = new AiCache(backend, PROVIDERS, present, c.now);
  await cache.refreshOnOpen();
  assert.deepEqual(cache.servers, one);
  backend.aiDiscover = async () => undefined;
  c.advance(REFRESH_GAP_MS + 1);
  await cache.refreshOnOpen();
  assert.deepEqual(cache.servers, one, "a failed read wipes nothing");
});

// Parked minors B (Task 6, part 2): B19 a rejected check keeps the list it held; B20 the note a failed server look-up shows.
test("loadCloud: a rejected check keeps the list it held and records the failure in works, so the Keys card shows the error", async () => {
  const failing = new Set();
  const cache = new AiCache(fakeBackend({ failing }), PROVIDERS, present, clock().now);
  assert.equal(await cache.loadCloud("anthropic"), true);
  const held = cache.models.anthropic;
  failing.add("anthropic");
  assert.equal(await cache.loadCloud("anthropic"), false);
  assert.deepEqual(cache.models.anthropic, held, "a failed read is not an empty one");
  assert.equal(cache.works.anthropic.ok, false);
  assert.match(cache.works.anthropic.text, /key was rejected/);
});

test("refreshOnOpen: a held list whose check failed is still stale, so the next open tries again", async () => {
  const failing = new Set();
  const t = clock();
  const cache = new AiCache(fakeBackend({ failing }), PROVIDERS, present, t.now);
  await cache.refreshOnOpen();
  failing.add("anthropic");
  t.advance(MODEL_LIST_MAX_AGE_MS + 1);
  await cache.refreshOnOpen();
  assert.ok(cache.models.anthropic, "the list is held");
  failing.delete("anthropic");
  t.advance(REFRESH_GAP_MS + 1);
  const before = cache.works.anthropic;
  await cache.refreshOnOpen();
  assert.equal(cache.works.anthropic.ok, true, "the next open tried again and it worked");
  assert.notEqual(cache.works.anthropic, before);
});

test("discoveryMsg: a failed look-up shows its note; a list (even an empty one) shows none; an earlier message stays unless it is that note", () => {
  const note = "Couldn't look for servers.";
  assert.equal(discoveryMsg(undefined, null), note, "no answer: the note");
  assert.equal(discoveryMsg(undefined, "Couldn't save."), note, "no answer replaces another message with the note");
  assert.equal(discoveryMsg([], null), null, "an empty list is an answer");
  assert.equal(discoveryMsg([], "That doesn't look like a URL."), "That doesn't look like a URL.", "a successful Rescan keeps an earlier message");
  assert.equal(discoveryMsg([], note), null, "a later answer takes the failure note away");
});
