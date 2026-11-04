// The control map's Windows and Linux column (tests/fixtures/settings/controls.json: winHomes, win, winOnly, winPages). Every stored key the Windows Settings reads or writes
// sits under exactly one control, with its store; the source scans make a key that the hand list misses still fail. The Mac ignores these fields (SettingsMap.swift).
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { PAGES, pageTitle, tabs } from "../../src/settings/route.ts";

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const fixture = JSON.parse(fs.readFileSync(new URL("../../../tests/fixtures/settings/controls.json", import.meta.url), "utf8"));
const all = [...fixture.controls, ...(fixture.winOnly ?? [])];

/** Every stored key the Windows and Linux Settings use, by store. `local` keys are the window's own storage and are not frozen. */
const FROZEN = {
  settings: [
    "soundEnabled", "soundVolume", "openOnHover", "hoverGlow", "focusAware", "tuckAway", "autoCloseInterval", "autostart", "activeIntegrations", "hooksInstalled",
    "ai.claudeCodeEnabled", "ai.claudeCodeModel", "ai.chat", "ai.files", "ai.preferredCloud", "ai.cloudModels", "ai.customServer", "ai.localModels", "ai.lastUsedLocal",
    "cat.character", "cat.collar", "cat.cats.<id>.collar", "cat.furLines", "cat.desktop.on", "cat.desktop.size", "cat.desktop.spots", "cat.outfit",
    "cat.cats.<id>.personality", "cat.motionStyle", "cat.cats.<id>.motion", "cat.displayMode", "cat.pair", "cat.agentCats", "cat.projectCats",
    "sidekick.on", "sidekick.dismissals", "sidekick.local",
    "companion.humor", "companion.seeSessions",
    "screen",
  ],
  credential: [
    "anthropic-api-key", "google-api-key", "openai-api-key", "custom-server-key.default", "resend-api-key", "n8n-url", "n8n-api-key", "vercel-token", "github-token",
    "stripe-api-key", "calcom-api-key", "notion-api-key", "link.peer.<id>", "link.peers", "link.static-key", "link.device-id",
  ],
  file: ["~/.claude/settings.json", "~/.gemini/settings.json", "~/.gemini/config/hooks.json"],
  link: ["visible", "deviceName"],
};

/** A key the settings page covers: the exact key, or a `<prefix>.` family the frozen list spells out. */
const covered = (key) => FROZEN.settings.some((s) => s === key || (key.endsWith(".") && s.startsWith(key)));

/** The field names of `export interface <name> { … }`: its own lines, or a one-line body split at its semicolons. */
function fieldsOf(src, name) {
  const lines = src.split("\n");
  const start = lines.findIndex((l) => l.startsWith(`export interface ${name} {`));
  assert.ok(start >= 0, `${name} is declared`);
  const body = lines[start].trimEnd().endsWith("}")
    ? lines[start].slice(lines[start].indexOf("{") + 1, lines[start].lastIndexOf("}")).split(";")
    : lines.slice(start + 1, lines.findIndex((l, i) => i > start && l === "}"));
  return body.map((l) => /^\s*(\w+)\??:/.exec(l)?.[1]).filter(Boolean);
}

const settingsSources = () => fs.readdirSync(new URL("../../src/settings/", import.meta.url)).filter((f) => f.endsWith(".ts")).map((f) => read(`src/settings/${f}`)).join("\n");
const servicesSource = () => /export const SERVICES[\s\S]*?\n\];/.exec(read("src/settings/services.ts"))[0];
const cloudSource = () => /CLOUD_PROVIDERS = \[([\s\S]*?)\] as const/.exec(read("src/core/bridge.ts"))[1];
const customKeySource = () => /export const CUSTOM_KEY = "([^"]+)"/.exec(read("src/settings/ai.ts"))[1];
const quoted = (line) => [...line.matchAll(/"([^"]+)"/g)].map((m) => m[1]);

/** The credential names the Settings sources use: a literal passed to a secret call, every `key: "…"` property of SERVICES or CLOUD_PROVIDERS (labelled or not), the
 * suffix-named literals, and the custom server's key. A `key:` property anywhere else is not a credential. */
function credentialNamesOf({ settings, services, cloud, customKey }) {
  const names = new Set();
  for (const m of settings.matchAll(/secret(?:Set|Presence|Clear)\(\s*"([^"]+)"/g)) names.add(m[1]);
  for (const m of settings.matchAll(/"([a-z0-9]+(?:-[a-z0-9]+)*-(?:api-key|token|url|key))"/g)) names.add(m[1]);
  for (const m of [...services.matchAll(/\bkey: "([^"]+)"/g), ...cloud.matchAll(/\bkey: "([^"]+)"/g)]) names.add(m[1]);
  names.add(customKey);
  return names;
}

/** The card titles the Settings sources give: each `card("<name>"` call, and each listed title. */
function cardTitlesOf({ settings, listed }) {
  const titles = new Set([...settings.matchAll(/card\("([^"]+)"/g)].map((m) => m[1]));
  for (const t of listed) titles.add(t);
  return titles;
}

test("shape: every control and winOnly entry has winHomes and win arrays, and the ids are unique", () => {
  for (const c of all) {
    assert.ok(Array.isArray(c.winHomes), `${c.id}: winHomes`);
    assert.ok(Array.isArray(c.win), `${c.id}: win`);
  }
  const ids = all.map((c) => c.id);
  assert.equal(new Set(ids).size, ids.length, "control ids are unique across controls and winOnly");
});

test("homes: each Windows home is a page of the Settings, and its tab is null or one the page shows", () => {
  for (const c of all) for (const h of c.winHomes) {
    assert.ok(PAGES.includes(h.page), `${c.id}: page ${h.page}`);
    const shown = tabs(h.page, { companion: true });
    if (shown.length === 0) assert.equal(h.tab, null, `${c.id}: ${h.page} shows no tab`);
    else assert.ok(shown.includes(h.tab), `${c.id}: ${h.tab} is a tab of ${h.page}`);
  }
});

test("pages: winPages lists the six pages with the tabs this platform shows", () => {
  assert.deepEqual(fixture.winPages, PAGES.map((p) => ({ page: p, title: pageTitle(p), tabs: tabs(p) })));
});

test("frozen keys: each sits under exactly one control with the same store; every win key is frozen or local", () => {
  for (const [store, keys] of Object.entries(FROZEN)) for (const key of keys) {
    const owners = all.filter((c) => c.win.some((w) => w.key === key && w.store === store));
    assert.equal(owners.length, 1, `${store} ${key} sits under exactly one control`);
  }
  for (const c of all) for (const w of c.win) {
    if (w.store === "local") continue;
    assert.ok(FROZEN[w.store]?.includes(w.key), `${c.id}: ${w.store} ${w.key} is frozen`);
  }
  assert.equal(all.length, 57, "the map holds 56 controls and winOnly's screen");
});

test("source scan, settings: every field of Settings, AiSettings and the cat block is a frozen key", () => {
  const state = read("src/core/state.ts");
  for (const f of fieldsOf(state, "Settings")) {
    if (f === "ai" || f === "cat" || f === "sidekick") continue;
    if (f === "companion") {
      // The Companion block is held by its two keys: the page writes only those (the others stay as the store keeps them).
      assert.ok(covered("companion.humor") && covered("companion.seeSessions"), "Settings.companion is covered by companion.humor and companion.seeSessions");
      continue;
    }
    assert.ok(FROZEN.settings.includes(f), `Settings.${f} is frozen`);
  }
  const companionWrites = [...read("src/settings/companion.ts").matchAll(/write\(\{ (\w+):/g)].map((m) => m[1]).sort();
  assert.deepEqual(companionWrites, ["humor", "seeSessions"], "settings/companion.ts writes only companion.humor and companion.seeSessions");
  for (const f of fieldsOf(state, "AiSettings")) assert.ok(covered(`ai.${f}`), `AiSettings.${f} is covered`);
  const catKeys = [
    ...fieldsOf(read("src/cat/settings.ts"), "CatSettings").map((f) => (f === "cats" ? "cat.cats." : `cat.${f}`)),
    ...fieldsOf(read("src/cat/display.ts"), "DisplaySettings").map((f) => `cat.${f}`),
    ...fieldsOf(read("src/cat/desktop.ts"), "DesktopSettings").map((f) => `cat.desktop.${f}`),
    "cat.outfit",
    "cat.projectCats",
  ];
  for (const k of catKeys) assert.ok(covered(k), `the cat block's ${k} is covered`);
  for (const f of fieldsOf(read("src/sidekick/core.ts"), "SidekickSettings")) assert.ok(covered(`sidekick.${f}`), `SidekickSettings.${f} is covered`);
});

test("credential scan: a key property of SERVICES counts with or without a label, a secret call's literal counts, and a key property elsewhere does not", () => {
  const names = credentialNamesOf({
    settings: 'const x = { key: "other-thing" }; secretPresence("zz-api-key");',
    services: '{ id: "a", fields: [{ key: "new-token-x", secret: true }] }',
    cloud: "",
    customKey: "custom-server-key.default",
  });
  assert.ok(names.has("new-token-x"), "a SERVICES key with no label is a credential");
  assert.ok(names.has("zz-api-key"), "a literal passed to secretPresence is a credential");
  assert.ok(!names.has("other-thing"), "a key property outside SERVICES and CLOUD_PROVIDERS is not");
});

test("card scan: a title is a card(\"...\") call or a listed title, and the same words in a plain string are not a card", () => {
  const titles = cardTitlesOf({ settings: 'card("Look", null, row("Look", x))', listed: ["Resend"] });
  assert.ok(titles.has("Look") && titles.has("Resend"));
  assert.ok(!cardTitlesOf({ settings: 'const hint = "Collar"; row("Collar", x)', listed: [] }).has("Collar"), "a row label is not a card");
});

test("source scan, credentials: every credential name the Settings page uses is a credential key", () => {
  const names = credentialNamesOf({ settings: settingsSources(), services: servicesSource(), cloud: cloudSource(), customKey: customKeySource() });
  assert.ok(names.size >= 12, "the scan found the Settings' credential names");
  for (const n of names) assert.ok(FROZEN.credential.includes(n), `credential ${n} is frozen`);
});

test("source scan, link: the link's settings file holds visible and deviceName", () => {
  const rs = read("src-tauri/src/link/settings.rs");
  assert.ok(rs.includes("visible") && rs.includes("deviceName"), "link/settings.rs names visible and deviceName");
});

test("the Mac's fields keep their shape: mac is {key, store} and homes is {page, tab, card}", () => {
  for (const c of fixture.controls) {
    for (const m of c.mac) assert.deepEqual(Object.keys(m).sort(), ["key", "store"], `${c.id}: mac entry`);
    for (const h of c.homes) assert.deepEqual(Object.keys(h).sort(), ["card", "page", "tab"], `${c.id}: home`);
  }
});

test("the cards: every card of the Windows map is a card title in a Settings page file: a card(\"...\") call, or a listed title (a SERVICES name, a provider's KEY_TITLES name, a hook card's TITLES)", () => {
  const listed = [
    ...[...servicesSource().matchAll(/name: "([^"]+)"/g)].map((m) => m[1]),
    ...quoted(/const KEY_TITLES[^\n]*/.exec(read("src/settings/airows.ts"))[0]).flatMap((t) => [t, t.replace(/ API key$/, "")]),
    ...quoted(/const TITLES[^\n]*/.exec(read("src/settings/agents.ts"))[0]),
  ];
  const titles = cardTitlesOf({ settings: settingsSources(), listed });
  const cards = new Set();
  for (const c of all) for (const home of c.winHomes) if (home.card && home.card !== "(the shell)") cards.add(home.card);
  assert.ok(cards.has("Where you code"), "the Agents page's card is in the map");
  assert.ok(cards.size >= 20, `${cards.size} cards`);
  // A group card's name is its members joined by ", ": each member is a card title.
  for (const card of cards) for (const name of card.split(", ")) assert.ok(titles.has(name), `card "${name}" is a card title in src/settings`);
});
