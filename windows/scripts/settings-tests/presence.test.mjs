// Tri-state presence (settings/tauri polish, Task 1): a key is present, absent or unreadable. An unreadable store is never shown as "No key yet" and never overwritten.
// The rules are replayed here (DraftBook, presenceChip, the Your AI rows); the wiring is pinned as text, because Node has no DOM.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DraftBook, canStartWrite, saveDisabled } from "../../src/settings/drafts.ts";
import { presenceChip, keyChip, tone, savedNote } from "../../src/settings/status.ts";
import * as Rows from "../../src/settings/airows.ts";
import { sliceBetween } from "./slice.mjs";

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const bridge = read("src/core/bridge.ts");
const backend = read("src/settings/backend.ts");
const app = read("src/settings/app.ts");
const kit = read("src/settings/kit.ts");
const services = read("src/settings/services.ts");
const ai = read("src/settings/ai.ts");
const devseed = read("src/settings/devseed.ts");
const drafts = read("src/settings/drafts.ts");
const island = read("src/island/integrations.ts");
const chat = read("src/views/chat.ts");
const rust = read("src-tauri/src/lib.rs");
const secrets = read("src-tauri/src/secrets.rs");

const I = {
  claudeState: "signedIn", claudeEnabled: true, claudeModel: "sonnet",
  keys: ["openai"], cloudModel: { anthropic: "claude-sonnet-5-5", openai: "gpt-6.1-sol" },
  servers: [], memory: {},
};

// ── Rules ─────────────────────────────────────────────────────────────────────

test("DraftBook: an unreadable key is not saved and, with nothing typed, not dirty", () => {
  const d = new DraftBook({ "resend-api-key": "unreadable", "anthropic-api-key": "present", "stripe-api-key": "absent" });
  assert.equal(d.isUnreadable("resend-api-key"), true);
  assert.equal(d.isSaved("resend-api-key"), false, "unreadable is not saved");
  assert.equal(d.isDirty("resend-api-key"), false, "nothing typed, so not dirty");
  assert.equal(d.presenceOf("resend-api-key"), "unreadable");
  assert.equal(d.isSaved("anthropic-api-key"), true);
  assert.equal(d.presenceOf("anthropic-api-key"), "present");
  assert.equal(d.isUnreadable("stripe-api-key"), false);
  assert.equal(d.presenceOf("stripe-api-key"), "absent");
  assert.equal(d.presenceOf("nope"), undefined, "a key the book never read has no presence, not absent");
});

test("DraftBook.canWrite: unreadable is refused; present and absent are writable; a key outside the list is writable; a listed key never read is refused", () => {
  const d = new DraftBook(
    { "resend-api-key": "unreadable", "anthropic-api-key": "present", "stripe-api-key": "absent" },
    ["resend-api-key", "anthropic-api-key", "stripe-api-key", "github-token"],
  );
  assert.equal(d.canWrite("resend-api-key"), false, "unreadable: no write, no removal");
  assert.equal(d.canWrite("anthropic-api-key"), true, "present");
  assert.equal(d.canWrite("stripe-api-key"), true, "absent");
  assert.equal(d.canWrite("custom-server-key.default"), true, "outside the key list: not read at boot, so writable");
  assert.equal(d.canWrite("github-token"), false, "in the key list but never read: refused, not taken for absent");
});

test("DraftBook.canWrite: typed text is kept while unreadable, and a fresh look that finds the key stored makes it writable", () => {
  const d = new DraftBook({ "resend-api-key": "unreadable" }, ["resend-api-key"]);
  d.edit("resend-api-key", " re_123 ");
  assert.equal(d.canWrite("resend-api-key"), false);
  assert.equal(d.isDirty("resend-api-key"), true, "the typed text is still a draft");
  d.setPresence("resend-api-key", "present");
  assert.equal(d.canWrite("resend-api-key"), true, "after Check again finds the store readable");
  assert.equal(d.text("resend-api-key"), " re_123 ", "the typed text is kept across the presence change");
});

test("DraftBook.writableDirty: a card's Save writes its writable drafts only, so an unreadable n8n key does not block the URL", () => {
  const d = new DraftBook({ "n8n-url": "absent", "n8n-api-key": "unreadable" }, ["n8n-url", "n8n-api-key"]);
  d.edit("n8n-url", "https://n8n.example.com");
  d.edit("n8n-api-key", "typed-but-unwritable");
  assert.deepEqual(d.writableDirty(["n8n-url", "n8n-api-key"]), ["n8n-url"]);
  d.edit("n8n-url", "   ");
  assert.deepEqual(d.writableDirty(["n8n-url", "n8n-api-key"]), [], "spaces alone are not a draft");
});

test("DraftBook: a successful write or removal settles an unreadable key, and markSaved keeps its meaning", () => {
  const d = new DraftBook({ "github-token": "unreadable" });
  d.edit("github-token", "ghp_x");
  d.markSaved("github-token", true);
  assert.equal(d.isSaved("github-token"), true);
  assert.equal(d.isUnreadable("github-token"), false);
  assert.equal(d.text("github-token"), "");
  d.setPresence("github-token", "unreadable");
  d.markSaved("github-token", false);
  assert.equal(d.presenceOf("github-token"), "absent");
});

test("presenceChip: unreadable says Couldn't read; present and absent defer to keyChip", () => {
  assert.equal(presenceChip("unreadable"), "Couldn't read");
  assert.equal(presenceChip("present"), keyChip(true));
  assert.equal(presenceChip("absent"), keyChip(false));
  assert.equal(presenceChip("absent"), "No key yet");
  assert.equal(tone("Couldn't read"), "warn");
  assert.equal(tone("Couldn't read the credential store"), "warn");
});

test("Your AI rows: an unreadable key is not ready, its chip says the store cannot be read, and it is never No key yet", () => {
  const r = { kind: "key", provider: "anthropic" };
  const U = { ...I, keys: [], unreadable: ["anthropic"] };
  assert.equal(Rows.chip(r, U), "Couldn't read the credential store");
  assert.equal(tone(Rows.chip(r, U)), "warn");
  assert.equal(Rows.makeMain(r, U).kind, "unavailable");
  assert.equal(Rows.reasonLine(r, U), null, "the chip already says it");
  assert.equal(Rows.helpLine(r, U), null);
  assert.equal(Rows.isUnreadable(U, r), true);
  assert.equal(Rows.chip(r, { ...I, keys: [] }), "No key yet", "an absent key still says No key yet");
});

test("Your AI rows: the unreadable input defaults to none, so every existing input chips as before", () => {
  const r = { kind: "key", provider: "google" };
  assert.equal(Rows.chip(r, I), "No key yet");
  assert.equal(Rows.chip({ kind: "key", provider: "openai" }, I), "Ready");
  assert.equal(Rows.chip(r, { ...I, unreadable: [] }), "No key yet");
});

// ── Wiring (text pins) ────────────────────────────────────────────────────────

test("bridge.ts: the Settings window asks for secret_presence; the island's secret_present stays as it was", () => {
  assert.match(bridge, /secretPresence: \(key: string\) => call<"present" \| "absent" \| "unreadable">\("secret_presence", \{ key \}\)/);
  assert.match(bridge, /secretPresent: \(key: string\) => call<boolean>\("secret_present", \{ key \}\)/);
  assert.match(island, /Bridge\.secretPresent\(key\)/, "the island's integrations page still calls secretPresent");
  assert.match(chat, /Bridge\.secretPresent\(c\.key\)/, "the chat view still calls secretPresent");
});

test("backend.ts: secretPresence returns a Presence, and a null bridge answer is unreadable, never absent", () => {
  assert.match(backend, /secretPresence\(key: string\): Promise<Presence>;/);
  assert.doesNotMatch(backend, /secretPresent\(/, "the Settings backend no longer has secretPresent");
  assert.match(backend, /secretPresence: async \(key\) => \(await Bridge\.secretPresence\(key\)\) \?\? "unreadable"/);
});

test("app.ts: the eleven keys load with secretPresence into a book that knows the key list", () => {
  assert.match(app, /for \(const k of KEYS\) present\[k\] = await backend\.secretPresence\(k\);/);
  assert.doesNotMatch(app, /secretPresent\(k\)\) \?\? false/);
  assert.match(app, /Record<string, Presence>/);
  assert.match(app, /new DraftBook\(present, KEYS\)/, "the book gets the key list, so a key never read is refused");
});

test("drafts.ts: canWrite is the one write gate, and writableDirty filters through it", () => {
  assert.match(drafts, /ids\.filter\(\(id\) => this\.canWrite\(id\) && this\.isDirty\(id\)\)/);
  assert.match(drafts, /if \(p === undefined\) return !this\.#keys\.has\(id\);/);
});

test("the Rust side: secret_presence is registered and secret_present is still there for the island", () => {
  assert.match(rust, /#\[tauri::command\]\nasync fn secret_presence\(key: String\) -> secrets::Presence/);
  assert.match(rust, /^\s+secret_presence,$/m, "registered in the invoke handler");
  assert.match(rust, /#\[tauri::command\]\nasync fn secret_present\(key: String\) -> bool/);
  // The keyring can wait for an unlock: both probes run off the main thread, and a task that did not come back is "no" (the island) or unreadable (Settings).
  assert.match(rust, /async fn secret_presence[^{]*\{\s*blocking\(move \|\| secrets::presence\(&key\)\)\.await\.unwrap_or\(secrets::Presence::Unreadable\)\s*\}/);
  assert.match(rust, /async fn secret_present[^{]*\{\s*blocking\(move \|\| secrets::present\(&key\)\)\.await\.unwrap_or\(false\)\s*\}/);
  assert.match(secrets, /pub fn classify\(result: Result<String, keyring::Error>\) -> Presence/);
});

test("kit.ts: a disabled key field keeps its held draft (the value is set before the disabled return); checkAgain sets the answer, runs onPresent when stored, then repaints", () => {
  const at = kit.indexOf("export function keyField(");
  const body = kit.slice(at, kit.indexOf("\n}\n", at));
  assert.ok(body.indexOf("input.value = o.drafts.text(o.id)") >= 0 && body.indexOf("input.value = o.drafts.text(o.id)") < body.indexOf("if (o.disabled)"), "the held draft is set before the disabled return");
  assert.match(body, /input\.disabled = true;/);
  assert.match(kit, /ctx\.backend\.secretPresence\(id\)/);
  assert.match(kit, /ctx\.drafts\.setPresence\(id, p\);/);
  assert.match(kit, /if \(p === "present" && onPresent\) await onPresent\(\);/);
  assert.match(kit, /button\("Check again"/);
});

test("services.ts: a card's Save writes the writable drafts through writableDirty; Remove goes through canWrite; the unreadable key is disabled with its help line and Check again", () => {
  assert.match(services, /for \(const id of ctx\.drafts\.writableDirty\(keys\)\) \{\n\s+try \{\n\s+const typed = ctx\.drafts\.text\(id\);\n\s+await ctx\.backend\.secretSet\(id, typed\.trim\(\)\);/);
  assert.match(services, /async function removeKey\(f: ServiceField\): Promise<void> \{\n\s+(?:\/\/[^\n]*\n\s+)?if \(!canStartWrite\(writing\.has\(def\.id\)\) \|\| !ctx\.drafts\.canWrite\(f\.key\)\) return;/);
  assert.match(services, /const on = ctx\.drafts\.writableDirty\(keys\)\.length > 0;/, "Save is enabled when a writable field is dirty");
  assert.match(services, /checkAgain\(ctx, f\.key, \(\) => paint\(def\), undefined, `\$\{def\.name\} \$\{f\.label\}`\)/, "named by its card and field, like Remove");
  assert.match(services, /Couldn't read the credential store\./);
  assert.match(services, /Can't read the credential store/);
});

test("ai.ts: the Keys tab's save and remove check canWrite before the write or the removal; Check again loads the models once stored; no Add a key for an unreadable key", () => {
  assert.match(ai, /async function saveKey\(p: KeyProvider, save: HTMLButtonElement\): Promise<void> \{\n\s+const c = entry\(p\);\n\s+if \(!c \|\| !canStartWrite\(writing\.has\(p\)\) \|\| !ctx\.drafts\.canWrite\(c\.key\)\) return;\n[\s\S]*?await ctx\.backend\.secretSet\(c\.key, text\)/);
  assert.match(ai, /async function removeKey\(p: KeyProvider\): Promise<void> \{\n\s+const c = entry\(p\);\n(?:\s*\/\/[^\n]*\n)*\s+if \(!c \|\| !canStartWrite\(writing\.has\(p\)\) \|\| !ctx\.drafts\.canWrite\(c\.key\)\) return;\n[\s\S]*?await ctx\.backend\.secretClear\(c\.key\)/);
  assert.match(ai, /checkAgain\(ctx, c\.key, \(\) => paintKey\(p\), \(\) => ctx\.ai\.loadCloud\(p\), `\$\{c\.brand\} key`\)/);
  assert.match(ai, /Couldn't read the credential store\./);
  assert.match(ai, /Can't read the credential store/);
  assert.match(ai, /!input\.keys\.includes\(r\.provider\) && !Rows\.isUnreadable\(input, r\)/, "no Add a key for an unreadable key");
  assert.match(ai, /const providersWhere = /, "one helper for the key lists");
});

test("devseed.ts: the error sample's unreadable keys are the Services Resend key and the Anthropic key. Not run in Node: devseed imports ai.ts, which imports ../views/dom without an extension", () => {
  assert.match(devseed, /const UNREADABLE: readonly string\[\] = \["resend-api-key", "anthropic-api-key"\];/);
  assert.match(devseed, /secretPresence: async \(key\) => \(state === "error" && UNREADABLE\.includes\(key\) \? "unreadable" : SAVED\[state\]\.includes\(key\) \? "present" : "absent"\)/);
  assert.doesNotMatch(devseed, /secretPresent:/);
});

// ── Parked minors A/B (Task 6, part 1): the credential rows, the saves and the AI cache ──

/** A function's text from its marker to the line that closes it at `indent` ("" at the top level, "  " or "    " inside a page factory). */
const bodyOf = (text, marker, indent = "") => sliceBetween(text, marker, `\n${indent}}\n`);
test("savedNote: an unreadable typed field that stayed unsaved gets the readable-ones notice; otherwise the usual one", () => {
  assert.equal(savedNote(false), "Saved. It never touches disk.");
  assert.equal(savedNote(true), "Saved the readable ones.");
});

test("services.ts: saveAll's final notice is chosen by savedNote over the unreadable typed fields that stayed unsaved", () => {
  const body = bodyOf(services, "    async function saveAll(): Promise<void> {", "    ");
  assert.match(body, /savedNote\(ctx\.drafts\.anyDirty\(keys\.filter\(\(id\) => ctx\.drafts\.isUnreadable\(id\)\)\)\)/);
  assert.doesNotMatch(body, /notice\("ok", "Saved\. It never touches disk\."\)/, "the usual sentence comes from savedNote only");
});

test("drafts.ts: canStartWrite and saveDisabled, the Save guard by outcome: no second write while one is in flight; Save is off while writing or with nothing writable typed", () => {
  assert.equal(canStartWrite(false), true, "a card with no write in flight may start one");
  assert.equal(canStartWrite(true), false, "a card with a write in flight may not start another");
  assert.equal(saveDisabled(false, true), false, "typed and idle: Save on");
  assert.equal(saveDisabled(false, false), true, "nothing typed: Save off");
  assert.equal(saveDisabled(true, true), true, "a write in flight: Save off even when text was typed since");
  assert.equal(saveDisabled(true, false), true);
});

test("services.ts: Save is guarded per card by a writing flag: saveAll returns early when set, dirty() respects it, and the flag clears in finally", () => {
  assert.match(services, /const writing = new Set<string>\(\);/, "one flag per card, kept across repaints");
  const body = bodyOf(services, "    async function saveAll(): Promise<void> {", "    ");
  assert.match(body, /if \(!canStartWrite\(writing\.has\(def\.id\)\)\) return;/);
  assert.match(body, /writing\.add\(def\.id\);/);
  assert.match(body, /finally \{\s*\n\s*writing\.delete\(def\.id\);[\s\S]*?live\.get\(def\.id\)\?\.dirty\(\);\s*\n\s*\}/, "the flag clears, then the current card is refreshed");
  assert.match(services, /save\.disabled = saveDisabled\(writing\.has\(def\.id\), on\);/, "dirty() keeps Save off while writing");
  assert.match(services, /import \{[^}]*canStartWrite[^}]*saveDisabled[^}]*\} from "\.\/drafts\.ts";|import \{ canStartWrite, saveDisabled \} from "\.\/drafts\.ts";/);
});

test("services.ts: every Remove is named by its card and its field, so no two Remove buttons share a name", () => {
  assert.match(services, /rm\.setAttribute\("aria-label", `Remove \$\{def\.name\} \$\{f\.label\}`\);/);
  assert.match(services, /const rm = button\("Remove", \(\) => void removeKey\(f\), "danger"\);/);
});

test("ai.ts: Save is guarded per provider by a writing flag: saveKey returns early when set, update() respects it, and the Remove is named by its provider", () => {
  assert.match(ai, /const writing = new Set<KeyProvider>\(\);/);
  const body = bodyOf(ai, "  async function saveKey(p: KeyProvider, save: HTMLButtonElement): Promise<void> {", "  ");
  assert.match(body, /if \(!c \|\| !canStartWrite\(writing\.has\(p\)\) \|\| !ctx\.drafts\.canWrite\(c\.key\)\) return;/);
  assert.match(body, /writing\.add\(p\);/);
  assert.match(body, /writing\.delete\(p\);/);
  assert.doesNotMatch(body, /try \{\s*\n\s*try \{/, "one try, not a try inside a try");
  assert.match(ai, /save\.disabled = saveDisabled\(writing\.has\(p\), dirty\);/, "update() keeps Save off while writing");
  assert.match(ai, /const rm = button\("Remove", \(\) => void removeKey\(p\), "danger"\);/);
  assert.match(ai, /rm\.setAttribute\("aria-label", `Remove \$\{c\.brand\} key`\);/);
});

test("ai.ts aiInput: the window's cloud lists and each server's status reach the signature, as Rust's routing reads them", () => {
  const at = ai.indexOf("export function aiInput(");
  const body = ai.slice(at, ai.indexOf("\n}\n", at));
  assert.match(body, /cloudIds: /, "the lists' ids are passed");
  assert.match(body, /status: x\.status/, "each server's status is passed");
});

test("kit.ts checkAgain: a rejected presence read is unreadable (never absent) and the card repaints", () => {
  const body = bodyOf(kit, "export function checkAgain(", "");
  assert.match(body, /\.catch\(\(\): Presence => "unreadable"\)/);
  assert.match(kit, /import \{ tone, type Presence \} from "\.\/status\.ts";/);
});

test("kit.ts rowOf: aria-labelledby only on a control with no name of its own (an aria-label, an aria-labelledby, or a button's text)", () => {
  const body = bodyOf(kit, "function rowOf(", "");
  assert.match(body, /!namesItself\(c\)/);
  const named = bodyOf(kit, "function namesItself(c: HTMLElement): boolean {", "");
  assert.match(named, /c\.hasAttribute\("aria-label"\)/);
  assert.match(named, /c\.hasAttribute\("aria-labelledby"\)/);
  assert.match(named, /c\.matches\("button"\) && \(c\.textContent \?\? ""\)\.trim\(\) !== ""/, "a select's options are not its name; a button's text is");
});

test("kit.ts checkAgain: sets the answer, repaints, runs onPresent when stored, repaints again; a .then chain, not an immediately-run async", () => {
  const body = bodyOf(kit, "export function checkAgain(", "");
  const set = body.indexOf("ctx.drafts.setPresence(id, p);");
  const first = body.indexOf("repaint();");
  const on = body.indexOf('if (p === "present" && onPresent) await onPresent();');
  const last = body.lastIndexOf("repaint();");
  assert.ok(set > 0 && set < first && first < on && on < last, "setPresence, repaint, onPresent, repaint");
  assert.match(body, /void ctx\.backend\.secretPresence\(id\)\.catch\(\(\): Presence => "unreadable"\)\.then\(async \(p\) => \{/);
  assert.doesNotMatch(body, /void \(async/);
});

// Parked minors B (Task 6, part 2), B18: a write clears what was typed only when the text still equals what was sent.
test("drafts.ts markSaved: text typed while the write runs is kept and the field stays dirty; the text that was sent is cleared", () => {
  const book = new DraftBook({ "stripe-api-key": "absent" }, ["stripe-api-key"]);
  book.edit("stripe-api-key", "sk_test_1");
  const sent = book.text("stripe-api-key");
  book.edit("stripe-api-key", "sk_test_12");
  book.markSaved("stripe-api-key", true, sent);
  assert.equal(book.text("stripe-api-key"), "sk_test_12", "typed during the write: kept");
  assert.equal(book.isDirty("stripe-api-key"), true, "still a draft");
  assert.equal(book.isSaved("stripe-api-key"), true, "the write did land");

  book.markSaved("stripe-api-key", true, "sk_test_12");
  assert.equal(book.text("stripe-api-key"), "", "unchanged since it was sent: cleared");
  assert.equal(book.isDirty("stripe-api-key"), false);
});

test("drafts.ts markSaved: a removal (no sent text) clears what is typed, as before", () => {
  const book = new DraftBook({ "stripe-api-key": "present" }, ["stripe-api-key"]);
  book.edit("stripe-api-key", "typed");
  book.markSaved("stripe-api-key", false);
  assert.equal(book.text("stripe-api-key"), "");
  assert.equal(book.isSaved("stripe-api-key"), false);
});

test("kit.ts checkAgain: two Check again buttons in one card are told apart by a label that still contains the visible words", () => {
  const body = bodyOf(kit, "export function checkAgain(", "");
  assert.match(body, /label\?: string/);
  assert.match(body, /if \(label\) check\.setAttribute\("aria-label", `Check again: \$\{label\}`\)/);
});

test("app.ts KEYS is exactly the credential keys the pages draw (Services fields, cloud providers), all allowed by Rust, and never the added server's key", () => {
  const keys = [...sliceBetween(app, "const KEYS = [", "] as const;").matchAll(/"([a-z0-9-]+)"/g)].map((m) => m[1]);
  assert.ok(keys.length >= 11, "the list was read");
  const services_ = [...services.matchAll(/\{ key: "([a-z0-9-]+)"/g)].map((m) => m[1]);
  const providers = [...sliceBetween(bridge, "export const CLOUD_PROVIDERS = [", "] as const;").matchAll(/key: "([a-z0-9-]+)"/g)].map((m) => m[1]);
  assert.ok(services_.length >= 8 && providers.length === 3, "both page lists were read");
  assert.deepEqual([...keys].sort(), [...services_, ...providers].sort(), "a key a page draws but KEYS lacks would show 'No key yet' for a stored key and skip the unreadable guard");
  const allowed = [...sliceBetween(secrets, "pub const KNOWN_KEYS: &[&str] = &[", "];").matchAll(/"([a-z0-9-]+)"/g)].map((m) => m[1]);
  for (const k of keys) assert.ok(allowed.includes(k), `${k} is on Rust's allow-list`);
  const custom = /export const CUSTOM_KEY = "([^"]+)"/.exec(ai)[1];
  assert.ok(!keys.includes(custom), "the added server's key is the one deliberate outsider (it is never read at boot)");
});
