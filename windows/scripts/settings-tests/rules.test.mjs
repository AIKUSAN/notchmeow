// The pure rules of the restyled Settings (windows/src/settings/route, layout, status, drafts, sidekicktab and withMuted), each held to the Mac's rule of the same name.
// The drift pins that tie the words to the Swift sources are in drift.test.mjs.
import test from "node:test";
import assert from "node:assert/strict";
import { PAGES, pageTitle, tabs, tabTitle, tabKey, pageColor, migrate, tabFor, placeOrCurrent, placeWithStored, focusAfter, alreadyShown, focusTarget } from "../../src/settings/route.ts";
import { sidebarMode, columnWidth, displayPath, displayText, closeAfter } from "../../src/settings/layout.ts";
import { slots, pillSwitch, hookChip, keyChip, serviceChip, tone, CAP_SENTENCE, nextActive, hookCardChip, claudeBackupNote, UNREADABLE_SETTINGS, UNREADABLE_CONFIG, unusableHelp } from "../../src/settings/status.ts";
import { DraftBook } from "../../src/settings/drafts.ts";
import { STUCK_KINDS, STUCK_NAMES, stuckSwitch, example } from "../../src/settings/sidekicktab.ts";
import { withMuted, withUnmuted } from "../../src/sidekick/settings.ts";
import { cleanSidekickSettings } from "../../src/sidekick/core.ts";

test("route: the pages, their titles and colours", () => {
  assert.deepEqual(PAGES, ["general", "agents", "chat", "services", "cat", "devices"]);
  assert.deepEqual(PAGES.map(pageTitle), ["General", "Agents", "AI and chat", "Services", "Cat", "Devices"]);
  assert.deepEqual(PAGES.map(pageColor), ["#8E939C", "#3B9EFF", "#E07950", "#7C5CFF", "#D9A066", "#5B8DEF"]);
  assert.equal(tabKey("cat"), "settingsTab.cat");
});

test("route: the tabs each page shows", () => {
  assert.deepEqual(tabs("general"), []);
  assert.deepEqual(tabs("general", { shortcuts: true }), ["general", "shortcuts"]);
  assert.deepEqual(tabs("chat"), ["yourai", "keys", "localmodels", "sidekick", "companion"]);
  assert.deepEqual(tabs("chat", { companion: false }), ["yourai", "keys", "localmodels", "sidekick"]);
  assert.equal(tabTitle("companion"), "Companion");
  assert.deepEqual(tabs("cat").map(tabTitle), ["Look", "Outfits", "Personality", "Agents' cats"]);
  for (const p of ["agents", "services", "devices"]) assert.deepEqual(tabs(p), []);
  assert.ok(PAGES.every((p) => tabs(p).length <= 5), "the chat has five tabs with Companion");
});

test("route: migrate reads old tags, bare pages and <page>/<tab>, and falls back to General", () => {
  const M = (s) => migrate(s);
  assert.deepEqual(M("activepills"), { page: "general", tab: null });
  assert.deepEqual(M("integrations"), { page: "services", tab: null });
  assert.deepEqual(M("shortcuts"), { page: "general", tab: null });
  assert.deepEqual(M("sidekick"), { page: "chat", tab: "sidekick" });
  for (const p of PAGES) assert.deepEqual(M(p), { page: p, tab: null });
  for (const bad of [null, undefined, "", "Chat", "bogus", "yourai", "/keys", "nope/keys", "chat/keys/x", "chat/", "Chat/keys"]) assert.deepEqual(M(bad), { page: "general", tab: null }, String(bad));
  assert.deepEqual(M("chat/keys"), { page: "chat", tab: "keys" });
  assert.deepEqual(M("chat/look"), { page: "chat", tab: null });
  assert.deepEqual(M("chat/companion"), { page: "chat", tab: "companion" });
  assert.deepEqual(M("general/shortcuts"), { page: "general", tab: null });
  assert.deepEqual(M("agents/keys"), { page: "agents", tab: null });
  for (const p of PAGES) for (const t of tabs(p)) assert.deepEqual(M(`${p}/${t}`), { page: p, tab: t });
});

test("route: tabFor keeps a shown stored tab, else the first one, else none", () => {
  assert.equal(tabFor("cat", "outfits"), "outfits");
  assert.equal(tabFor("cat", "keys"), "look");
  assert.equal(tabFor("chat", "companion"), "companion");
  assert.equal(tabFor("agents", "keys"), null);
  assert.equal(tabFor("general", "shortcuts"), null);
});

test("layout: the sidebar mode and the column width", () => {
  const W = [415, 559, 560, 599, 600, 720, 1100, 3000];
  assert.deepEqual(W.map(sidebarMode), ["icons", "icons", "icons", "icons", "expanded", "expanded", "expanded", "expanded"]);
  assert.deepEqual(W.map(columnWidth), [327, 471, 472, 511, 360, 480, 640, 640]);
  for (let w = 415; w <= 3000; w++) assert.ok(columnWidth(w) >= 327, String(w));
  assert.equal(columnWidth(40), 0);
});

test("layout: displayPath shows the home as ~, Windows case-insensitively and POSIX exactly", () => {
  const home = String.raw`C:\Users\sam`;
  assert.equal(displayPath(String.raw`C:\Users\sam\.claude\settings.json`, home), String.raw`~\.claude\settings.json`);
  assert.equal(displayPath(String.raw`c:\users\SAM\AppData\Local\NotchMeow\bin\notchmeow-hook.exe`, home), String.raw`~\AppData\Local\NotchMeow\bin\notchmeow-hook.exe`);
  assert.equal(displayPath(String.raw`D:\Tools\NotchMeow\bin\notchmeow-hook.exe`, home), String.raw`D:\Tools\NotchMeow\bin\notchmeow-hook.exe`);
  assert.equal(displayPath(home, home), "~");
  assert.equal(displayPath(String.raw`C:\Users\samuel\x`, home), String.raw`C:\Users\samuel\x`);
  assert.equal(displayPath("/home/sam/.gemini/settings.json", "/home/sam"), "~/.gemini/settings.json");
  assert.equal(displayPath("/home/Sam/x", "/home/sam"), "/home/Sam/x", "POSIX is case-sensitive");
  assert.equal(displayPath("/opt/notchmeow/bin/notchmeow-hook", "/home/sam"), "/opt/notchmeow/bin/notchmeow-hook");
  assert.equal(displayPath("/a/b", ""), "/a/b");
});

test("layout: displayText replaces the home inside a preview, escaped forms included", () => {
  const home = String.raw`C:\Users\sam`;
  assert.equal(displayText(String.raw`+  "command": "C:\\Users\\sam\\AppData\\Local\\NotchMeow\\bin\\notchmeow-hook.exe --agent gemini"`, home),
    String.raw`+  "command": "~\\AppData\\Local\\NotchMeow\\bin\\notchmeow-hook.exe --agent gemini"`);
  assert.equal(displayText(String.raw`+  "command": "c:\\users\\SAM\\AppData\\x.exe"`, home), String.raw`+  "command": "~\\AppData\\x.exe"`);
  assert.equal(displayText(String.raw`Backup → C:\Users\sam\.claude\settings.json.bak-20261018`, home), String.raw`Backup → ~\.claude\settings.json.bak-20261018`);
  assert.equal(displayText('"command": "/home/sam/.local/share/notchmeow/bin/notchmeow-hook"', "/home/sam"), '"command": "~/.local/share/notchmeow/bin/notchmeow-hook"');
  assert.equal(displayText(String.raw`{"command":"\/Users\/name\/.claude\/notchmeow\/nm-hook"}`, "/Users/name"), String.raw`{"command":"~\/.claude\/notchmeow\/nm-hook"}`);
  assert.ok(!/sam/i.test(displayText(String.raw`C:\\Users\\sam\\x and C:\Users\sam\y`, home)));
  assert.equal(displayText(String.raw`C:\Users\samuel\x`, home), String.raw`C:\Users\samuel\x`);
});

test("status: slots, the cap and the switch of a pill", () => {
  const cat = [{ id: "agent_gemini", name: "Gemini CLI" }, { id: "integration_resend", name: "Resend" }, { id: "integration_github", name: "GitHub" }];
  assert.deepEqual(slots(["integration_github", "agent_gemini"], cat), { text: "2 of 4 slots used", names: ["Gemini CLI", "GitHub"], full: false });
  assert.equal(slots(["integration_github", "integration_resend", "agent_gemini", "integration_gone"], cat).full, true);
  assert.deepEqual(pillSwitch(false, true, 4, "x"), { showsSwitch: false, chip: "Main", disabled: false });
  assert.deepEqual(pillSwitch(false, false, 4, null), { showsSwitch: true, chip: "4 of 4 slots used. Turn another off.", disabled: true });
  assert.equal(pillSwitch(true, false, 4, null).disabled, false);
  assert.deepEqual(pillSwitch(false, false, 1, "Hooks not installed"), { showsSwitch: true, chip: "Hooks not installed", disabled: false });
});

test("status: the chips and their tones", () => {
  assert.deepEqual([hookChip(true, true), hookChip(true, false), hookChip(false, false), hookChip(null, false)], ["Needs update", "Installed", "Not installed", null]);
  assert.deepEqual([keyChip(true), keyChip(false), serviceChip(true), serviceChip(false)], ["Ready", "No key yet", "Saved", "No key yet"]);
  assert.deepEqual(["Ready", "Running, 4 models", "Installed", "Saved", "Main", "Needs update", "Not saved", CAP_SENTENCE, "Off", "Not ready", "No key yet", "Coming with the new chat", "Server off"].map(tone),
    ["ok", "ok", "ok", "ok", "ok", "warn", "warn", "warn", "warn", "error", "neutral", "neutral", "neutral"]);
});

test("drafts: typed text is a draft, a saved value is only its presence", () => {
  const d = new DraftBook({ "anthropic-api-key": "present", "resend-api-key": "absent" });
  assert.equal(d.text("anthropic-api-key"), ""); assert.ok(!d.isDirty("anthropic-api-key")); assert.ok(d.isSaved("anthropic-api-key"));
  d.edit("resend-api-key", "  "); assert.ok(!d.isDirty("resend-api-key"), "spaces alone are not a draft");
  d.edit("resend-api-key", " re_123 "); assert.ok(d.isDirty("resend-api-key")); assert.ok(d.anyDirty(["n8n-url", "resend-api-key"]));
  assert.ok(!d.isDirty("anthropic-api-key"), "another field is untouched");
  d.setPresence("resend-api-key", "absent"); assert.equal(d.text("resend-api-key"), " re_123 ");
  d.markSaved("resend-api-key", true); assert.equal(d.text("resend-api-key"), ""); assert.ok(d.isSaved("resend-api-key")); assert.ok(!d.isDirty("resend-api-key"));
  d.edit("anthropic-api-key", "sk-new"); d.clearTyped(); assert.equal(d.text("anthropic-api-key"), ""); assert.ok(d.isSaved("anthropic-api-key"));
  d.markSaved("anthropic-api-key", false); assert.ok(!d.isSaved("anthropic-api-key"));
  assert.equal(d.text("nope"), ""); assert.ok(!d.isSaved("nope"));
});

test("sidekick tab: the stuck switch, its names and the example lines", () => {
  assert.deepEqual(stuckSwitch(() => false), { on: true, detail: null });
  assert.deepEqual(stuckSwitch((k) => k.startsWith("stuck.")), { on: false, detail: null });
  assert.deepEqual(stuckSwitch((k) => k !== "stuck.loop" && k.startsWith("stuck.")), { on: true, detail: "1 of 4" });
  assert.deepEqual(stuckSwitch((k) => k === "stuck.loop"), { on: true, detail: "3 of 4" }, "one muted: three still show");
  assert.deepEqual(stuckSwitch((k) => k === "stuck.loop" || k === "stuck.silent"), { on: true, detail: "2 of 4" }, "two muted: two still show");
  assert.deepEqual(STUCK_NAMES.map((n) => n.label), ["Repeated steps", "Repeated errors", "Waiting for your OK", "Gone quiet"]);
  assert.equal(STUCK_KINDS.length, 4);
  assert.equal(example("stuck.loop"), "Claude Code has run the same step 4 times.");
  assert.equal(example("stuck.errors"), "Claude Code hit 3 errors in a row.");
  assert.equal(example("stuck.waiting"), "Claude Code is still waiting for your OK.");
  assert.equal(example("stuck.silent"), "Claude Code has been quiet for 5 minutes.");
  assert.ok(example("recap")?.startsWith("While you were away, Claude Code in my-app"));
  for (const k of ["recap", ...STUCK_KINDS]) assert.ok(!(example(k) ?? "/").includes("/") && !(example(k) ?? "\\").includes("\\"), k);
  assert.equal(example("risk"), null);
});

test("sidekick tab: withMuted mutes a kind, and withUnmuted clears it", () => {
  const s0 = cleanSidekickSettings(null);
  assert.equal(withMuted(s0, "recap").dismissals.recap, 2);
  assert.equal(withMuted({ ...s0, dismissals: { ...s0.dismissals, recap: 1 } }, "recap").dismissals.recap, 2);
  assert.equal(withUnmuted(withMuted(s0, "stuck.loop"), "stuck.loop").dismissals["stuck.loop"], 0);
  assert.deepEqual(s0, cleanSidekickSettings(null), "withMuted does not change its input");
});

test("status: nextActive adds a pill under the four-slot cap, removes one, and changes nothing when the switch already says so", () => {
  const four = ["integration_stripe", "integration_resend", "integration_n8n", "integration_vercel"];
  const three = four.slice(0, 3);
  assert.equal(nextActive(four, "agent_gemini", true), null, "four on and a fifth asked: no change");
  assert.deepEqual(nextActive(three, "agent_gemini", true), [...three, "agent_gemini"], "three on and one more: four");
  assert.deepEqual(nextActive(four, "integration_n8n", false), ["integration_stripe", "integration_resend", "integration_vercel"], "one off: three");
  assert.equal(nextActive(three, "integration_n8n", true), null, "already on");
  assert.equal(nextActive(three, "agent_gemini", false), null, "already off");
  const five = [...four, "agent_gemini"];
  assert.equal(nextActive(five, "agent_antigravity", true), null, "a stale five-id list does not grow");
  assert.deepEqual(nextActive(five, "agent_gemini", false), four, "a stale five-id list can still lose one");
});

test("general: closeAfter reads the field as seconds, 5 to 120, and 15 when it holds no number", () => {
  assert.equal(closeAfter(""), 15);
  assert.equal(closeAfter("abc"), 15);
  assert.equal(closeAfter("0"), 15);
  assert.equal(closeAfter("3"), 5);
  assert.equal(closeAfter("200"), 120);
  assert.equal(closeAfter("30"), 30);
});

test("route: placeOrCurrent keeps the page on screen for a well-formed place whose page is unknown; every other place reads through migrate", () => {
  const cur = { page: "services", tab: null };
  assert.deepEqual(placeOrCurrent("zzz", cur), cur, "an unknown page keeps the current page");
  assert.deepEqual(placeOrCurrent("zzz/keys", cur), cur, "an unknown page with a tab keeps the current page");
  assert.deepEqual(placeOrCurrent("chat/keys", cur), { page: "chat", tab: "keys" }, "a known place is read");
  assert.deepEqual(placeOrCurrent("devices", cur), { page: "devices", tab: null });
  assert.deepEqual(placeOrCurrent("chat/zzz", cur), { page: "chat", tab: null }, "a known page with an unshown tab is the page");
  assert.deepEqual(placeOrCurrent("sidekick", cur), { page: "chat", tab: "sidekick" }, "a legacy tag is a known place");
  assert.deepEqual(placeOrCurrent("activepills", cur), { page: "general", tab: null }, "a legacy tag reads through migrate");
  assert.deepEqual(placeOrCurrent("Chat", cur), { page: "general", tab: null }, "a malformed word is General, as migrate says");
  assert.deepEqual(placeOrCurrent("chat/keys/x", cur), { page: "general", tab: null }, "a malformed path is General");
  assert.deepEqual(placeOrCurrent(null, cur), { page: "general", tab: null }, "no place is General, as migrate says");
});

test("route: placeWithStored gives a bare page the tab stored for it (injected storage), keeps a named tab, and falls back to the first tab", () => {
  const store = new Map([["settingsTab.cat", "outfits"], ["settingsTab.chat", "look"]]);
  const read = (k) => store.get(k) ?? null;
  assert.deepEqual(placeWithStored({ page: "cat", tab: null }, read), { page: "cat", tab: "outfits" }, "a bare page remembers its last tab");
  assert.deepEqual(placeWithStored({ page: "cat", tab: "personality" }, read), { page: "cat", tab: "personality" }, "a named tab wins over the stored one");
  assert.deepEqual(placeWithStored({ page: "chat", tab: null }, read), { page: "chat", tab: "yourai" }, "a stored tab the page does not show gives its first");
  assert.deepEqual(placeWithStored({ page: "cat", tab: null }, () => null), { page: "cat", tab: "look" }, "nothing stored gives the first tab");
  assert.deepEqual(placeWithStored({ page: "general", tab: null }, read), { page: "general", tab: null }, "a page with no tabs keeps none");
  assert.deepEqual(placeWithStored({ page: "services", tab: null }, read), { page: "services", tab: null });
});

// Parked minors B (Task 6, part 2): one legacy table for migrate and placeOrCurrent, and the keyboard focus after a page or tab is chosen.
test("route: placeOrCurrent reads the legacy tags through the same table as migrate, and a prototype name is an unknown page", () => {
  const cur = { page: "cat", tab: "look" };
  assert.deepEqual(placeOrCurrent("integrations", cur), { page: "services", tab: null }, "the Services page");
  assert.deepEqual(placeOrCurrent("integrations", cur), migrate("integrations"));
  assert.deepEqual(placeOrCurrent("shortcuts", cur), { page: "general", tab: null }, "the Shortcuts tag falls to General while its tab is not shown");
  assert.deepEqual(placeOrCurrent("shortcuts", cur), migrate("shortcuts"));
  assert.deepEqual(placeOrCurrent("activepills", cur), migrate("activepills"));
  assert.deepEqual(placeOrCurrent("sidekick", cur), migrate("sidekick"));
  assert.deepEqual(placeOrCurrent("constructor", cur), cur, "an inherited name is an unknown page, not a legacy tag");
});

test("route: focusAfter says where keyboard focus goes after a page or tab is chosen: the sidebar button, the tab, or the sidebar when the page has no tab", () => {
  assert.equal(focusAfter(null, { page: "cat", tab: "look" }), null, "no focus on a sidebar or tab button: focus stays where it is");
  assert.equal(focusAfter("nav", { page: "cat", tab: "look" }), "nav");
  assert.equal(focusAfter("nav", { page: "services", tab: null }), "nav");
  assert.equal(focusAfter("tab", { page: "cat", tab: "outfits" }), "tab", "a tab chosen by keyboard keeps focus on a tab");
  assert.equal(focusAfter("tab", { page: "services", tab: null }), "nav", "a page with no tabs takes the focus to its sidebar button");
});

test("route: alreadyShown is true for the page on screen (a bare page, or its own tab), so a repeated place is not built again", () => {
  const cur = { page: "chat", tab: "keys" };
  assert.equal(alreadyShown({ page: "chat", tab: null }, cur), true, "a bare page on screen");
  assert.equal(alreadyShown({ page: "chat", tab: "keys" }, cur), true, "the tab on screen");
  assert.equal(alreadyShown({ page: "chat", tab: "yourai" }, cur), false, "another tab of the page is a change");
  assert.equal(alreadyShown({ page: "cat", tab: null }, cur), false, "another page is a change");
});

test("route: focusTarget sends the focus to the tab menu when the tab bar is narrow (its buttons are hidden), else to the selected tab", () => {
  assert.equal(focusTarget(true), "menu");
  assert.equal(focusTarget(false), "tab");
});

test("hookCardChip: an unreadable settings.json or a failed read says Couldn't read; a held status says its chip; nothing yet says Checking", () => {
  assert.equal(hookCardChip({ installed: false, error: UNREADABLE_SETTINGS }, false), "Couldn't read");
  assert.equal(hookCardChip({ installed: false, error: null }, false), "Not installed");
  assert.equal(hookCardChip({ installed: true }, false), "Installed");
  assert.equal(hookCardChip(null, true), "Couldn't read");
  assert.equal(hookCardChip(null, false), "Checking…");
  assert.equal(UNREADABLE_SETTINGS, "Couldn't read settings.json.");
  assert.equal(UNREADABLE_CONFIG, "Couldn't read the config file.");
  assert.equal(hookCardChip({ installed: false, error: UNREADABLE_CONFIG }, false), "Couldn't read", "a Gemini or Antigravity config that cannot be read is the same chip");
});

test("unusableHelp: the card names why the file cannot be used and what to do, from fixed words only", () => {
  assert.equal(unusableHelp(true, "not valid JSON"), "Couldn't read settings.json. It isn't valid JSON. Fix or move the file, then Check again.");
  assert.equal(unusableHelp(false, "not an object"), "Couldn't read the config file. It isn't a JSON object. Fix or move the file, then Check again.");
  assert.match(unusableHelp(true, "unreadable"), /^Couldn't read settings\.json\. It couldn't be opened\. Check that nothing else has it open/);
  assert.match(unusableHelp(false, "unexpected hooks shape"), /^Couldn't read the config file\. Its "hooks" section isn't in a shape NotchMeow can add to\. Fix or move the file, then Check again\.$/);
  // A reason this build does not know (or none at all) says nothing about the file and keeps the generic remedy.
  assert.equal(unusableHelp(true, null), "Couldn't read settings.json. Fix or move the file, then Check again.");
  assert.equal(unusableHelp(false, "something new"), "Couldn't read the config file. Fix or move the file, then Check again.");
  assert.doesNotMatch(unusableHelp(true, "constructor"), /undefined|function/, "a reason that is a property name of Object is not a reason");
});

test("claudeBackupNote: names the kept settings only when there was a file; otherwise says it was created", () => {
  const show = (p) => `~${p}`;
  assert.equal(claudeBackupNote("C:/u/.claude/settings.json.bak-1", show), "Previous settings saved as ~C:/u/.claude/settings.json.bak-1.");
  assert.equal(claudeBackupNote("", show), "The file didn't exist, so it was created.");
});
