// Pins for the Agents and Services pages (Settings restyle, Task 7). They read the source as text, because Node has no DOM: the layout, the writes and the
// absences the brief names are held here, and the pictures (windows/scripts/render-settings.sh) show the rest.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { holdsTypedText, tabs, tabTitle } from "../../src/settings/route.ts";
import { brainNameOf } from "../../src/settings/companionrules.ts";
import { DraftBook } from "../../src/settings/drafts.ts";
import { withLocal, defaultSidekick } from "../../src/sidekick/settings.ts";

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const agents = read("src/settings/agents.ts");
const services = read("src/settings/services.ts");
const app = read("src/settings/app.ts");
const state = read("src/core/state.ts");
const kit = read("src/settings/kit.ts");
const css = read("src/settings/settings.css");

const count = (text, needle) => text.split(needle).length - 1;

/** The text from `marker` to the first line that closes the block at `end` (the function body's own closing brace, two spaces in). */
function block(text, marker, end = "\n  };\n") {
  const start = text.indexOf(marker);
  assert.ok(start >= 0, `${marker} exists`);
  const stop = text.indexOf(end, start);
  assert.ok(stop > start, `${marker} closes`);
  return text.slice(start, stop + end.length);
}

// ── Agents and Services ───────────────────────────────────────────────────────

test("Agents: Where you code comes first, then the three hook cards in order", () => {
  // The titles live in one map and the cards are drawn from one list, so the order is read from those and from the page's own children.
  assert.ok(agents.includes('card("Where you code",'));
  const titles = ["claude: \"Claude Code hooks\"", "gemini: \"Gemini CLI hooks\"", "antigravity: \"Antigravity hooks\""].map((t) => agents.indexOf(t));
  assert.ok(titles.every((at) => at >= 0), "the three titles exist");
  assert.ok(titles[0] < titles[1] && titles[1] < titles[2], "Claude Code, then Gemini CLI, then Antigravity");
  assert.ok(agents.includes('const KINDS: readonly HookKind[] = ["claude", "gemini", "antigravity"];'));
  assert.match(agents, /h\("div", \{ style: STACK \}, where, \.\.\.KINDS/, "Where you code is the page's first child, with the gap");
});

test("Agents: the switches come from AGENT_SWITCHES and the cap rule of pillSwitch", () => {
  assert.match(agents, /AGENT_SWITCHES/);
  assert.match(agents, /pillSwitch\(/);
  assert.match(agents, /agentLabel\(/);
});

test("Agents: a cap chip sits under its own agent's label, as a line that spans the row, and never in the control beside the switch", () => {
  // switchRow puts the chip and the help line after the row's control (the switch alone), as grid lines that span both columns (kit.ts's .st-under).
  const sw = block(kit, "export function switchRow(", "\n}\n");
  assert.match(sw, /const chipSlot = h\("span", \{ class: "st-chipslot st-under" \}\)/, "the chip slot is an under-line");
  assert.match(sw, /const helpLine = o\.help \? h\("div", \{ class: "st-under" \}, help\(o\.help\)\) : null;/, "the help line is an under-line");
  assert.match(sw, /rowOf\(text, labelBlock, \[sw\], chipSlot, helpLine\)/, "the row's control is the switch alone; the chip and help come after it");
  assert.doesNotMatch(sw, /\[chipSlot, sw\]/, "the control group does not hold the chip");
  assert.match(sw, /text\.classList\.toggle\("st-disabled", p\.disabled\)/, "the dim covers the label and the help, never the chip");
  assert.doesNotMatch(sw, /chipSlot\.contains/, "the chip is a sibling of the label and the help, so no click on them can come from it: no guard");
  assert.match(sw, /labelBlock\.addEventListener\("click", fromLabel\);/, "a click on the label toggles the switch");
  // Agents draws its switches through switchRow and places no chip of its own.
  assert.match(agents, /switchRow\(agentLabel\(id\), \{\s*on: st\.on, chip: st\.chip, disabled: st\.disabled,/);
  assert.doesNotMatch(agents, /chipSlot|st-chipslot/);
});

test("Switch and chip rows: a row of one short control is decided by kit.ts's SHORT rule, and a field or a menu keeps its own row", () => {
  const rowFn = block(kit, "export function row(", "\n}\n");
  assert.match(kit, /const shortRow = \(controls: readonly Node\[\]\): boolean => controls\.length > 0 && controls\.every\(isShort\);/, "one test of a short row, shared by row() and rowOf");
  assert.match(rowFn, /if \(shortRow\(controls\)\) \{\s*return rowOf\(text, h\("div", \{ class: "st-label" \}, text\), controls, note \? h\("div", \{ class: "st-under" \}, help\(note\)\) : null\);/, "the note goes under the label and the control");
  assert.match(kit, /const SHORT = "\.switch, \.st-chip, button, input\[type='range'\], input\[type='number'\], input\[type='checkbox'\], \.hint";/);
  assert.match(kit, /const isShort = \(c: Node\): boolean => c instanceof HTMLElement && \(c\.matches\(SHORT\) \|\| \(c\.matches\("\.st-wrap"\) && c\.children\.length > 0 && Array\.from\(c\.children\)\.every\(isShort\)\)\);/, "a wrapped group of short buttons (the Sidekick Unmute row) is short too");
  // A select or a text field is not short: its row stays the flex row that stacks under the label when they do not fit.
  // The help line of a row that is not short comes after its control (the Mac's order), in a line of its own, and the control names it (aria-describedby).
  assert.match(rowFn, /return rowOf\(text, h\("div", \{ class: "st-label" \}, text\), controls, line \? h\("div", \{ class: "st-under" \}, line\) : null\);/, "the label is its text only; the help is an under-line after the control");
  assert.match(rowFn, /c\.setAttribute\("aria-describedby", line\.id\)/, "the control is described by its help line");
  const underCss = css.slice(css.indexOf(".st-row > .st-under {"), css.indexOf("}", css.indexOf(".st-row > .st-under {")) + 1);
  assert.match(underCss, /flex: 0 0 100%/, "a non-short row's help line takes the whole row");
  assert.match(kit, /function rowOf\(text: HTMLElement, label: Node, controls: readonly Node\[\], \.\.\.under: \(Node \| null\)\[\]\): HTMLElement \{/, "rowOf takes no flag: the under-lines are its only extra");
  assert.match(kit, /class: shortRow\(controls\) \? "st-row st-short" : "st-row"/);
});

test("Labels: the label's text wraps by word, and a word wider than its column breaks inside it (anywhere; the 9em floor keeps a short row's label readable)", () => {
  const label = css.slice(css.indexOf(".st-labeltext {"), css.indexOf("}", css.indexOf(".st-labeltext {")) + 1);
  assert.match(label, /overflow-wrap: anywhere/, "a word that does not fit its column breaks inside it, and only then (a stacked row's label has no floor, so it needs this)");
  assert.doesNotMatch(label, /overflow-wrap: break-word/, "break-word would keep a long word whole in a stacked row's min-content and overflow the row");
});

test("Labels: the stress layout check gives a row with a wide nowrap control and a normal label, so the label keeps its floor and nothing overflows", () => {
  const dev = read("src/settings/devpanel.ts");
  assert.match(dev, /const probe = row\("Repeated errors", wrapRow\(/, "a probe row: a normal label beside a group of nowrap buttons");
  assert.match(dev, /probe\.dataset\.probe = "1"/, "the probe is marked, so the check reads its label's width");
  assert.match(dev, /import \{ button, row, select, wrapRow \} from "\.\/kit\.ts"/, "the probe is built by the kit's own row");
  assert.match(dev, /row\("AgentSessionLogsOnThisComputerForEveryAgentRun", select\(/, "a stacked probe: one 46-character unbreakable word beside a select, so the row stacks");
  assert.match(dev, /stacked\.dataset\.stacked = "1"/, "the stacked probe is marked, so the check reads its right edge");
});

test("Switch and chip rows: the grid's label column is at least 9em (a floor, so it is never a sliver beside a wide control) and 1fr, and an under-line spans both columns and sets no width", () => {
  const rule = css.slice(css.indexOf(".st-row.st-short {"), css.indexOf("}", css.indexOf(".st-row.st-short {")) + 1);
  assert.match(rule, /display: grid/);
  assert.match(rule, /grid-template-columns: minmax\(min\(9em, 100%\), 1fr\) auto/, "the label keeps 9em (about 117 px at 13 px), wrapping by word; the control keeps its own width and its group wraps inside");
  assert.match(rule, /align-items: center/);
  const under = css.slice(css.indexOf(".st-row.st-short > .st-under {"), css.indexOf("}", css.indexOf(".st-row.st-short > .st-under {")) + 1);
  assert.match(under, /grid-column: 1 \/ -1/, "the line spans both columns");
  assert.match(under, /contain: inline-size/, "the line's own width is not counted in the label column's minimum");
});

test("Agents: the stress sample's Gemini relay is not in place, with a long name that wraps, so the page shows a long notice", () => {
  // The notice names the relay's file (agents.ts), so the stress sample's long relay name is what wraps at 415. The ready sample keeps Gemini's relay ready.
  assert.match(agents, /const relay = status\.hookPath\.split\(\/\[\\\\\/\]\/\)\.pop\(\)/, "the notice names the relay's file");
  assert.match(agents, /is not in place yet\. Restart NotchMeow/);
  const seed = read("src/settings/devseed.ts");
  assert.ok(seed.includes("const longGemini = stress && agent === \"gemini\";"), "only stress changes Gemini's relay");
  assert.ok(seed.includes("hookReady: longGemini ? false : state !== \"empty\""), "stress: Gemini's relay is not ready; ready is unchanged");
  assert.match(seed, /GEMINI_RELAY_STRESS = `\$\{HOME\}\\\\AppData\\\\Local\\\\NotchMeow\\\\bin\\\\notchmeow-hook-gemini-with-a-long-build-label/, "the long name");
  assert.match(seed, /hookPath: longGemini \? GEMINI_RELAY_STRESS : /, "the status carries the long name");
});

test("Agents: the Where you code help line is the brief's wording", () => {
  assert.ok(agents.includes("On: the pill stays on the island and takes a slot. Off: it shows only while the agent is working."));
});

test("Agents: it says Hooks not installed, and names no codex, Plan usage or Cursor", () => {
  assert.ok(agents.includes("Hooks not installed"));
  assert.doesNotMatch(agents, /codex|Plan usage|Cursor/i);
});

test("Agents: every hook write sits in the confirm handler, after its label", () => {
  const confirm = agents.indexOf('"Back up and write"');
  assert.ok(confirm > 0, "the confirm button exists");
  assert.ok(agents.includes("hooksApply(install, preview.fingerprint)"), "Claude Code writes with the reviewed fingerprint");
  assert.ok(agents.includes("agentHooksApply(kind, install, preview.fingerprint)"), "the agents write with the reviewed fingerprint");
  const applies = [...agents.matchAll(/hooksApply\(|agentHooksApply\(/g)].map((m) => m.index);
  assert.equal(applies.length, 2, "exactly the two write calls");
  for (const at of applies) assert.ok(at > confirm, "each write is inside the confirm handler");
});

test("Agents: the preview shows the diff through displayText and the paths through displayPath", () => {
  assert.ok(agents.includes("displayText(preview.diff, ctx.home)"));
  assert.ok(count(agents, "displayPath(") >= 3, "the paths, the backup and the done line all go through displayPath");
  assert.match(agents, /hookCardChip\(status, failed\)/);
});

test("Agents: the install button is primary only when no hooks are installed", () => {
  assert.ok(agents.includes('class: status?.installed ? "" : "primary"'));
});

test("Agents: the refresh after a write updates the agent switch's chip", () => {
  const refresh = block(agents, "const refresh = async");
  assert.match(refresh, /\.set\(/, "the refresh sets the switch row");
  assert.match(refresh, /switchState\(/, "the chip comes from the one switch rule");
  assert.match(agents, /"Hooks not installed"/);
});

test("Agents: Copy gets the real path and the page shows the home as ~", () => {
  assert.match(agents, /pathDisclosure\(/);
  assert.match(agents, /shown: displayPath\(/);
  assert.doesNotMatch(agents, /path: displayPath\(/);
});

test("Agents and Services: one timer (the hook card's 2.6 s refresh, in agents.ts) and no observers", () => {
  assert.equal(count(agents, "setTimeout("), 1);
  assert.ok(agents.includes("window.setTimeout(refreshLater, 2600)"));
  assert.equal(count(services, "setTimeout("), 0);
  for (const src of [agents, services]) {
    assert.doesNotMatch(src, /setInterval|ResizeObserver|MutationObserver/);
  }
});

test("Services: a write is awaited in a try whose next statement marks the field saved", () => {
  assert.equal(count(services, "secretSet("), 1, "one write call");
  assert.match(services, /try \{\s*const typed = ctx\.drafts\.text\(id\);\s*await ctx\.backend\.secretSet\([^\n]*\);\s*ctx\.drafts\.markSaved\(/);
});

test("Services: the write's catch holds the refusal sentence and never marks the field saved", () => {
  const c = services.match(/catch\s*(\([^)]*\))?\s*\{[^}]*CREDENTIAL_SAVE_FAILED[^}]*\}/);
  assert.ok(c, "the catch shows the refusal");
  assert.doesNotMatch(c[0], /markSaved/);
  assert.ok(read("src/settings/status.ts").includes('CREDENTIAL_SAVE_FAILED = "Couldn\'t save to the credential store."'));
});

test("Services: a removal is awaited, and a refusal shows its own sentence", () => {
  assert.match(services, /await ctx\.backend\.secretClear\(/);
  assert.ok(services.includes("CREDENTIAL_REMOVE_FAILED"));
  assert.ok(read("src/settings/status.ts").includes('CREDENTIAL_REMOVE_FAILED = "Couldn\'t remove it from the credential store."'));
  assert.ok(services.includes("Key removed."));
});

test("Services: Save is disabled until something is typed, and primary only then", () => {
  assert.ok(services.includes("disabled: !ctx.drafts.anyDirty("));
  assert.match(services, /classList\.toggle\("primary"/);
  assert.ok(services.includes("savedNote("), "the final notice is savedNote's (the usual sentence or the readable-ones one)");
});

test("Services: a field with a draft shows Not saved", () => {
  assert.ok(services.includes('"Not saved"'));
});

test("Services: no Music card and no From field", () => {
  assert.doesNotMatch(services, /Music/);
  assert.doesNotMatch(services, /resend-from/);
});

test("Services: the seven services in the spec's order, and the same ids as the toggleable integrations", () => {
  const order = [...services.matchAll(/id: "(integration_[a-z0-9]+)"/g)].map((m) => m[1]);
  assert.deepEqual(order, [
    "integration_resend", "integration_n8n", "integration_vercel", "integration_github",
    "integration_stripe", "integration_calcom", "integration_notion",
  ]);
  const toggle = state.slice(state.indexOf("TOGGLEABLE_INTEGRATION_IDS"));
  const listed = [...toggle.slice(0, toggle.indexOf("];")).matchAll(/"(integration_[a-z0-9]+)"/g)].map((m) => m[1]);
  assert.deepEqual(new Set(order), new Set(listed));
});

test("Services: the page head is the brief's wording, and pillCatalog lists the agents then the services", () => {
  assert.ok(services.includes("Pick up to 4 pills to show next to your cat, counting the agents you turned on. Keys are stored in your system's credential store, never on disk."));
  assert.match(services, /export function pillCatalog\(/);
  assert.match(services, /AGENT_SWITCHES/);
});

test("app.ts builds the two pages, not their placeholders", () => {
  assert.ok(app.includes("case \"agents\": return agentsPage(ctx);"));
  assert.ok(app.includes("case \"services\": return servicesPage(ctx);"));
  assert.doesNotMatch(app, /case "agents": return placeholder\(\)/);
  assert.doesNotMatch(app, /case "services": return placeholder\(\)/);
});

// ── General and Devices (Settings restyle, Task 8) ────────────────────────────

const general = read("src/settings/general.ts");
const devices = read("src/settings/devices.ts");
const devseed = read("src/settings/devseed.ts");

test("General: four cards in the brief's order, and the closing line", () => {
  const cards = ['card("Sound"', 'card("Island"', 'card("On the island"', 'card("Startup"'].map((c) => general.indexOf(c));
  assert.ok(cards.every((at) => at >= 0), "the four cards exist");
  assert.ok(cards[0] < cards[1] && cards[1] < cards[2] && cards[2] < cards[3], "Sound, Island, On the island, Startup");
  assert.ok(general.includes("No telemetry. Network requests only go to the services you configure yourself."));
});

test("General: the Sound and Island rows are the brief's, with their words", () => {
  assert.ok(general.includes('switchRow("Enable sounds"'));
  assert.ok(general.includes('row("Volume"'));
  assert.ok(general.includes('switchRow("Open on hover"'));
  assert.ok(general.includes("Hovering the island opens it; it folds again shortly after the pointer leaves. Click inside to keep it open."));
  assert.ok(general.includes('switchRow("Hover glow"'));
  assert.match(general, /switchRow\("Hover glow"[\s\S]*?hoverGlow/);
  assert.ok(general.includes("A soft rainbow glow along the island's edge while the pointer is over it."));
  assert.ok(general.includes('row("Tuck the island away"'));
  assert.ok(general.includes('["never", "Never"]'));
  assert.ok(general.includes('["1", "After 1 min"]'));
  assert.ok(general.includes('["5", "After 5 min"]'));
  assert.ok(general.includes('["15", "After 15 min"]'));
  assert.ok(general.includes('["30", "After 30 min"]'));
  assert.ok(general.includes("The compact island hides by itself only when no agent is working or waiting, and this long has passed since the last hook event, alert or click on the island."));
  assert.match(general, /tuckAway/);
  assert.ok(general.includes('"Close after"'));
  assert.ok(general.includes('"seconds"'));
  assert.ok(general.includes("After you leave the island."));
  assert.ok(general.includes("closeAfter(") && !general.includes("Math.max(5"), "the clamp is layout.ts's closeAfter (its cases are in rules.test.mjs)");
  assert.match(read("src/settings/layout.ts"), /Math\.max\(5, Math\.min\(120, Number\(v\) \|\| 15\)\)/);
  assert.ok(general.includes('"Island lives on"'));
  assert.ok(general.includes('["primary", "Main display"]'));
  assert.ok(general.includes('["cursor", "Display under the cursor"]'));
  assert.ok(general.includes('switchRow("Launch at startup"'));
  // Task 5: the focus-awareness row sits between Open on hover and Hover glow, with the Mac's words.
  assert.ok(general.includes('switchRow("Step back when I\'m already in the app"'));
  assert.match(general, /switchRow\("Step back when I'm already in the app", \{\s*on: s0\.focusAware !== false,/);
  assert.ok(general.includes("When an agent asks for permission or a question while its app is in front, it asks there: the island stays closed and quiet, and an amber dot on its pill shows it is waiting."));
  assert.match(general, /onChange: \(v\) => void ctx\.save\(\{ \.\.\.ctx\.settings\(\), focusAware: v \}\)/);
  assert.match(general, /const island = card\("Island", null, hover\.el, stepBack\.el, glow\.el, tuckRow, closeRow, screenRow\);/);
  const hoverAt = general.indexOf('switchRow("Open on hover"'), stepAt = general.indexOf("switchRow(\"Step back when I'm already in the app\""), glowAt = general.indexOf('switchRow("Hover glow"');
  assert.ok(hoverAt > 0 && stepAt > hoverAt && glowAt > stepAt, "between Open on hover and Hover glow");
  assert.match(general, /glow\.set\(s\.hoverGlow\);\s*stepBack\.set\(s\.focusAware !== false\);/);
});

test("General: the On the island card names the slots and links each pill to its page", () => {
  assert.match(general, /slots\(/);
  assert.match(general, /pillCatalog\(/);
  assert.match(general, /s\.full \? "hint warn" : "hint"/, "the slots line is amber (class hint warn) when the four slots are full");
  assert.doesNotMatch(general, /\.names\b/, "the names are not read from slots: the link buttons come from the catalog");
  assert.match(general, /^  const catalog = pillCatalog\(\);$/m, "the catalog is read once, outside the repaint");
  assert.equal(count(general, "pillCatalog("), 1);
  assert.match(general, /^  const link = /m, "the link button maker is hoisted out of the repaint");
  assert.ok(general.includes("Each pill's switch is on the Agents or Services page."));
  assert.ok(general.includes('"agents"') && general.includes('"services"'), "the agents' and the services' links");
  assert.match(general, /AGENT_SWITCHES|startsWith\("agent_"\)/, "an agent's link opens Agents, a service's opens Services");
});

test("General: the link buttons are rebuilt only when the set of active pills changes, so a focused button survives a sync", () => {
  assert.match(general, /let linksKey = "";/);
  const check = general.indexOf("if (key === linksKey) return;");
  const rebuild = general.indexOf("linkHost.replaceChildren(");
  assert.ok(check > 0, "the key check exists");
  assert.ok(rebuild > check, "the link buttons are replaced only after the key check");
  assert.equal(count(general, "linkHost.replaceChildren("), 1, "one rebuild site");
  assert.equal(count(general, "slotBox.replaceChildren("), 0, "the whole box is never rebuilt");
  assert.match(general, /linksKey = key;/);
});

test("General: the line updates its text and class in place, not by replacing the node", () => {
  assert.match(general, /line\.textContent = s\.text;/);
  assert.match(general, /line\.className = /);
});

test("General: the ready sample's two pills are a General-only override; ACTIVE.ready (Services, Agents) keeps four", () => {
  assert.match(devseed, /GENERAL_READY_ACTIVE = \["agent_gemini", "integration_github"\]/);
  assert.ok(devseed.includes('ready: ["agent_gemini", "integration_resend", "integration_n8n", "integration_vercel"]'), "ACTIVE.ready is unchanged");
  assert.match(devseed, /page === "general"/, "the override is read only on the General page");
  assert.match(devseed, /sample === "ready" && !stress/, "stress keeps four");
});

test("General: the General page has no tab bar and no Shortcuts", () => {
  assert.doesNotMatch(general, /tabBar|Shortcuts/);
});

test("General: each change saves the whole settings with its one field, and writes go through setValue", () => {
  assert.match(general, /\.\.\.ctx\.settings\(\), /);
  assert.ok(count(general, "setValue(") >= 4, "the range, the selects and the number field sync through setValue");
  assert.match(general, /setValue\(volume/);
  assert.match(general, /volume\.disabled = !/, "the volume is disabled while sounds are off");
});

test("General: no timer and no observer", () => {
  assert.doesNotMatch(general, /setInterval|setTimeout|ResizeObserver|MutationObserver|IntersectionObserver/);
});

test("Devices: each machine's status dot has the chip's gap from its name", () => {
  // The name's span is a dot-label: the dot and the name sit in a row with the same 6 px gap the status chips use between their dot and their word.
  assert.match(devices, /h\("span", \{ class: "st-labeltext st-dotlabel" \}, h\("i", \{ class: "dot"/, "each machine's name carries the dot-label class");
  const rule = css.slice(css.indexOf(".st-dotlabel {"), css.indexOf("}", css.indexOf(".st-dotlabel {")) + 1);
  assert.match(rule, /display: inline-flex/);
  assert.match(rule, /align-items: flex-start/, "the dot sits on the name's first line, not the middle of a two-line name");
  assert.match(rule, /line-height: 16px/, "the first line is 16 px");
  assert.match(css, /\.st-dotlabel > \.dot \{ margin-top: 4px; \}/, "the 8 px dot's top is 4 px down: its centre is the first line's centre (16 / 2 = 4 + 8 / 2)");
  assert.match(rule, /gap: 6px/, "the chip's gap");
  const chipGap = css.slice(css.indexOf(".st-chip {"), css.indexOf("}", css.indexOf(".st-chip {")) + 1);
  assert.match(chipGap, /gap: 6px/, "the chip's own dot gap is the same 6 px");
  // A row with no chip keeps its label block's gaps: the empty slot takes no room and no gap.
  assert.ok(css.includes(".st-chipslot:empty { display: none; }"), "an empty chip slot is not a flex item");
});

test("Devices: no lk- machine rules, the three card titles and the stress-proof forget button", () => {
  assert.doesNotMatch(devices, /lk-(machine|mname|mstate|sub)/);
  assert.doesNotMatch(devices, /lk-machines/);
  for (const t of ['card("This computer"', 'card("Machines"', 'card("Received files"']) assert.ok(devices.includes(t), t);
  assert.ok(devices.includes("`Forget ${r.name}?`"));
  assert.match(devices, /class: "danger st-wrapbtn"/);
  assert.match(devices, /class: "st-wrapbtn"[^\n]*text: "Keep"|text: "Keep"[^\n]*st-wrapbtn/);
  assert.ok(devices.includes('"Keep"'));
  assert.ok(devices.includes('"Show folder"'));
  assert.match(devices, /wrapRow\(/);
});

test("Devices: the pairing gate's named listener is added and removed, and dispose still says false", () => {
  assert.ok(devices.includes('window.addEventListener("pagehide", onHide)'));
  assert.ok(devices.includes('window.removeEventListener("pagehide", onHide)'));
  assert.ok(devices.includes("const onHide = () => backend.setDevicesOpen(false);"));
  assert.doesNotMatch(devices, /addEventListener\("pagehide", \(\) =>/);
  // The real method (not the type's signature, which also reads "dispose()"), up to the end of its object.
  const start = devices.lastIndexOf("dispose() {");
  assert.ok(start > 0, "the dispose method exists");
  const dispose = devices.slice(start, devices.indexOf("\n    },", start));
  assert.ok(dispose.includes("off();"), "the snapshot listener is taken back");
  assert.ok(dispose.includes("observer.disconnect();"), "the observer is disconnected");
  assert.match(dispose, /removeEventListener\("visibilitychange"/);
  assert.match(dispose, /removeEventListener\("focus"/);
  assert.match(dispose, /removeEventListener\("pagehide", onHide\)/);
  assert.match(dispose, /backend\.setDevicesOpen\(false\)/);
});

test("Devices: the observer watches the first card, not the whole tall section, at threshold 0.2", () => {
  assert.match(devices, /observer\.observe\(computerCard\)/);
  assert.doesNotMatch(devices, /observer\.observe\(el\)/);
  assert.ok(devices.includes("threshold: 0.2"));
});

test("Devices: the section is a div of three cards and the section's own state and words stay", () => {
  assert.match(devices, /"div",\s*\{ id: "devices-section"/);
  assert.match(devices, /new IntersectionObserver\(/);
  assert.match(devices, /help\.style\.display = snap\.visible \? "" : "none";/);
  assert.match(devices, /setDevicesOpen\(open\)/);
  assert.doesNotMatch(devices, /setInterval|setTimeout|requestAnimationFrame|ResizeObserver|MutationObserver/);
});

test("Devices: no tab bar and no Shortcuts, and no third-party word the brief forbids", () => {
  assert.doesNotMatch(devices, /tabBar|Shortcuts|codex|Plan usage/i);
});

test("app.ts builds General and Devices, and the devices page wraps its dispose", () => {
  assert.ok(app.includes("case \"general\": return generalPage(ctx);"));
  assert.ok(app.includes("case \"devices\":"));
  assert.match(app, /const d = devicesSection\(\{ backend: ctx\.backend\.link, platform: ctx\.platform \}\);/);
  assert.match(app, /return \{ el: d\.el, dispose: \(\) => d\.dispose\(\) \};/);
  assert.doesNotMatch(app, /case "general": return placeholder\(\)/);
  assert.doesNotMatch(app, /case "devices": return placeholder\(\)/);
});

test("Devices: each machine row is a short row (the kit's rule: the name wraps in its column, the chip and the buttons sit beside it) and carries the machine marker the layout check reads", () => {
  assert.match(devices, /h\("div", \{ class: "st-row st-short", "data-machine": "" \}/, "a machine row is a st-row st-short with the data-machine marker");
  assert.match(devices, /h\("div", \{ class: "st-control" \}, chip\(stateWords\(r\.state\)\), wrapRow\(\.\.\.actions\)\)/, "the chip and the buttons are the one control");
});

test("Pop-up rows: a row whose pop-up has no width of its own takes a content-sized control (st-picker), so it sits beside its label when they fit; a full-width pop-up keeps its row", () => {
  assert.match(kit, /st-control st-picker/, "rowOf marks the control of a pop-up row");
  assert.match(kit, /c\.style\.width === ""/, "only a pop-up with no inline width of its own (a full-width pop-up keeps the row it has)");
  const rule = css.slice(css.indexOf(".st-control.st-picker {"), css.indexOf("}", css.indexOf(".st-control.st-picker {")) + 1);
  assert.match(rule, /flex: 1 1 auto/, "the control's basis is its pop-up's width, not 200 px");
});

test("Settings selects: a pop-up menu is content-sized, at most 180 px, and its row's control does not force a fixed width", () => {
  const rule = css.slice(css.indexOf(".st-control select {"), css.indexOf("}", css.indexOf(".st-control select {")) + 1);
  assert.match(rule, /max-width: 180px/, "a picker is at most 180 px");
  assert.doesNotMatch(rule, /(?<!max-)width: 180px/, "no fixed width: the pop-up is as wide as its longest option");
});

test("devseed: the ready sample has a server running with no models (the Local models chip 'Running, no models yet')", () => {
  assert.match(devseed, /status: "running",\s*models: \[\]/, "a running server with an empty model list");
});

test("Settings dev route: font=wide swaps the --font token for a wide stack and adds letter-spacing, only inside the DEV sample branch", () => {
  const main = read("src/settings/main.ts");
  assert.match(main, /const sample = import\.meta\.env\.DEV \? params\.get\("sample"\) : null;\n  if \(sample\) \{/, "the font route is inside the sample branch, which only the dev server takes");
  assert.match(main, /if \(params\.get\("font"\) === "wide"\) \{/, "the param is read on its own line");
  assert.match(main, /setProperty\("--font", 'Verdana, "Trebuchet MS", Arial, sans-serif'\)/, "a wide stack, Verdana first");
  assert.match(main, /setProperty\("letter-spacing", "0\.04em"\)/, "wider letter-spacing on the root, so the stand-in is wider whichever face is drawn");
  assert.doesNotMatch(read("src/settings/devpanel.ts"), /applyWideFont|WIDE_FONT/, "the font route lives in main.ts");
});

test("Layout check: the Forget confirm is measured by a dev hook (forget=1 presses the long machine's Forget, devpanel.ts)", () => {
  const main = read("src/settings/main.ts");
  assert.match(main, /reportLayout\(root, measure, params\.has\("stress"\), params\.has\("forget"\)\)/, "main passes forget to the measure");
  const dev = read("src/settings/devpanel.ts");
  assert.match(dev, /if \(forget\) \{/, "reportLayout presses Forget before it measures");
  assert.match(dev, /b\.textContent === "Forget"\)\?\.click\(\)/, "the long machine's own Forget button");
  const script = read("scripts/check-settings-layout.sh");
  assert.match(script, /\$url&forget/, "the layout check runs the Forget state in stress mode");
});

test("Layout check: the 'Running, no models yet' word is the one airows.ts draws", () => {
  const script = read("scripts/check-settings-layout.sh");
  assert.ok(script.includes('"Running, no models yet"'), "the layout check names the word");
  assert.ok(airowsSrc.includes('"Running, no models yet"'), "airows.ts draws it");
});

test("Layout check: the wide-font echo says what is drawn (a wide stack plus letter-spacing; the face is not detected)", () => {
  const script = read("scripts/check-settings-layout.sh");
  assert.match(script, /letter-spacing 0\.04em/);
  assert.match(script, /the face actually drawn is not detected/);
});

test("devseed: the stress sample adds the long-named row to the link snapshot, and the samples use the link seeds", () => {
  assert.ok(devseed.includes("A machine with a rather long name for testing the column"));
  assert.match(devseed, /import\("\.\.\/link\/devseed\.ts"\)/, "a dynamic import: the stand-in is loaded only on the dev server");
  assert.doesNotMatch(devseed, /from "\.\.\/link\/devseed/);
  assert.match(devseed, /"off"/);
  assert.match(devseed, /"problem"/);
  assert.match(devseed, /"on"/);
});

// ── AI and chat (Settings restyle, Task 9) ────────────────────────────────────

const AI_PATH = new URL("../../src/settings/ai.ts", import.meta.url);
/** ai.ts is read when a test needs it, so a missing file fails the tests that name it rather than the whole file. */
const aiSrc = () => {
  assert.ok(fs.existsSync(AI_PATH), "src/settings/ai.ts exists");
  return fs.readFileSync(AI_PATH, "utf8");
};
const ctxSrc = read("src/settings/ctx.ts");

/** The text of a function from its marker to its closing brace at its own indent (`indent` is "" at the top level, "  " inside a page factory). */
function fnBody(text, marker, indent = "") {
  const start = text.indexOf(marker);
  assert.ok(start >= 0, `${marker} exists`);
  const stop = text.indexOf(`\n${indent}}\n`, start);
  assert.ok(stop > start, `${marker} closes`);
  return text.slice(start, stop + 3);
}

test("AI: the context carries the AI cache, and app.ts builds it from the one provider list", () => {
  assert.match(ctxSrc, /ai: AiCache/);
  assert.match(app, /new AiCache\(backend, CLOUD_PROVIDERS,/);
  assert.match(app, /yourAiTab\(ctx, CLOUD_PROVIDERS\)/);
  assert.match(app, /keysTab\(ctx, CLOUD_PROVIDERS\)/);
  assert.match(app, /localModelsTab\(ctx\)/);
  assert.doesNotMatch(app, /case "yourai": return placeholder\(\)/);
});

test("AI: the cards, the prefer label and the Make main words are in ai.ts", () => {
  const ai = aiSrc();
  for (const t of [
    'card("Which one answers"', 'card("Choose your AI"', 'card("Local models"',
    '"When Auto picks a cloud model, prefer"', '"Claude API"', 'details("Details"',
    '"Make main"', '"Make main…"', "makeMain(", "isMain(", '"Not saved"', "setValue(",
    'import * as Rows from "./airows.ts"',
  ]) assert.ok(ai.includes(t), t);
});

test("AI: no Google plan, no Apple row, no ChatGPT wording, no paste box, no preferredCloud literal", () => {
  const ai = aiSrc();
  for (const t of ["Use my Google plan", "Google plan", "Apple", "ChatGPT", "Paste an API key", 'preferredCloud: "anthropic"']) {
    assert.ok(!ai.includes(t), t);
  }
});

test("the credential writes and clears never swallow an error: no secretSet or secretClear in ai.ts or services.ts takes a .catch; ai.ts's one .catch(() => undefined) is the discovery read", () => {
  // The call is cut at its own statement's semicolon, so a multi-line call is read whole and a .catch on a later statement is not taken for its own.
  for (const src of [aiSrc(), services]) {
    assert.doesNotMatch(src, /secret(?:Set|Clear)\([^;]*\)\s*\.catch\(/, "a credential write or clear with a .catch");
  }
  assert.equal(count(aiSrc(), ".catch(() => undefined)"), 1, "ai.ts has one .catch(() => undefined)");
  assert.match(aiSrc(), /await ctx\.backend\.aiDiscover\(\)\.catch\(\(\) => undefined\);/, "and it is the discovery read");
  assert.doesNotMatch(services, /\.catch\(\(\) => undefined\)/, "services.ts has none");
});

test("AI: the provider list is not named in ai.ts (app.ts passes it in), no value import of bridge.ts, no Bridge", () => {
  const ai = aiSrc();
  assert.doesNotMatch(ai, /CLOUD_PROVIDERS/);
  assert.doesNotMatch(ai, /^import (?!type )[^\n]*core\/bridge/m, "only type imports from bridge.ts");
  assert.doesNotMatch(ai, /Bridge\./);
});

test("AI: Make main writes only ai.chat, never files or the cloud preference", () => {
  const setMain = fnBody(aiSrc(), "async function setMain(", "  ");
  assert.match(setMain, /chat: choice/);
  assert.doesNotMatch(setMain, /files/);
  assert.doesNotMatch(setMain, /preferredCloud/);
});

test("AI: a key save awaits the write, marks it saved, then checks; a refusal returns before either", () => {
  const save = fnBody(aiSrc(), "async function saveKey(", "  ");
  const set = save.indexOf("await ctx.backend.secretSet(");
  const mark = save.indexOf("ctx.drafts.markSaved(");
  const load = save.indexOf("ctx.ai.loadCloud(");
  assert.ok(set >= 0 && set < mark && mark < load, "secretSet, then markSaved, then loadCloud");
  const catchAt = save.indexOf("catch", set);
  const ret = save.indexOf("return;", catchAt);
  assert.ok(catchAt > set && ret > catchAt && ret < mark, "the catch returns before markSaved");
  assert.doesNotMatch(save.slice(catchAt, ret), /markSaved|loadCloud/, "the catch holds no markSaved and no loadCloud");
  assert.doesNotMatch(save, /preferredCloud/, "a key save never writes preferredCloud");
  assert.ok(save.includes('"Saved. It never touches disk."'));
});

test("AI: a removal awaits the clear, forgets the list only after it, and a refusal stops", () => {
  const rm = fnBody(aiSrc(), "async function removeKey(", "  ");
  const clear = rm.indexOf("await ctx.backend.secretClear(");
  const forget = rm.indexOf("ctx.ai.forget(");
  assert.ok(clear >= 0 && forget > clear, "the clear is awaited before forget");
  assert.match(rm, /catch[\s\S]*?return;/);
  assert.ok(rm.includes('"Key removed."'));
  assert.ok(rm.includes("CREDENTIAL_REMOVE_FAILED"), "the Keys tab says what the Services cards say");
  assert.doesNotMatch(rm, /String\(err\)|Could not remove/, "the store's own text is never shown");
});

test("AI: a failed key write on the Keys tab shows the shared sentence, never the store's text", () => {
  const save = fnBody(aiSrc(), "async function saveKey(", "  ");
  assert.ok(save.includes("CREDENTIAL_SAVE_FAILED"));
  assert.doesNotMatch(save, /String\(err\)|Could not save|why/);
});

test("AI: Add server awaits both credential calls before the URL is saved, and each refusal returns", () => {
  const add = fnBody(aiSrc(), "async function addServer(", "  ");
  const set = add.indexOf("await ctx.backend.secretSet(CUSTOM_KEY");
  const clear = add.indexOf("await ctx.backend.secretClear(CUSTOM_KEY");
  const url = add.indexOf("customServer: url");
  assert.ok(set >= 0 && clear >= 0, "both calls exist");
  assert.ok(url > set && url > clear, "the URL is saved after both calls");
  for (const at of [set, clear]) {
    assert.match(add.slice(at, url), /catch[\s\S]*?return;/, "each call returns in its refusal path");
  }
  assert.doesNotMatch(add, /\.catch\(/);
  assert.ok(add.includes("That doesn't look like a URL."));
});

test("AI: Remove server saves first and clears its key after, and a refused save keeps both (it reads the saver's answer)", () => {
  const rm = fnBody(aiSrc(), "async function removeServer(", "  ");
  const clear = rm.indexOf("await ctx.backend.secretClear(CUSTOM_KEY");
  const forget = rm.indexOf("customServer: null");
  assert.ok(forget >= 0 && clear > forget, "the settings save comes first");
  assert.match(rm, /if \(!\(await ctx\.save\(\{[^\n]*customServer: null[^\n]*\}\)\)\) return;/, "a refused save returns before the key is touched");
  assert.doesNotMatch(rm, /\.catch\(/);
});

test("AI: Add server with no typed key clears a stored key before the save when no server is set or the origin differs (S1)", () => {
  const add = fnBody(aiSrc(), "async function addServer(", "  ");
  assert.match(add, /\} else if \(!before\.ai\.customServer \|\| originOf\(url\) !== originOf\(before\.ai\.customServer\)\) \{/);
  assert.ok(add.indexOf("await ctx.backend.secretClear(CUSTOM_KEY)") < add.indexOf("await ctx.save("), "the clear comes before the save");
});

test("AI: Add server reads the saver's answer; a refused save keeps the form and takes back only the key it just wrote", () => {
  const add = fnBody(aiSrc(), "async function addServer(", "  ");
  assert.match(add, /if \(!\(await ctx\.save\(\{[^\n]*customServer: url[^\n]*\}\)\)\) \{/);
  const refused = add.slice(add.indexOf("if (!(await ctx.save("), add.indexOf("if (key) ctx.drafts.markSaved(CUSTOM_KEY, true);"));
  assert.ok(refused.includes("await ctx.backend.secretClear(CUSTOM_KEY)") && refused.includes("return;"));
  assert.doesNotMatch(refused, /addOpen = false|ctx\.drafts\.edit|refreshServers/, "the form, the typed text and the list are left alone");
  assert.ok(add.indexOf("if (key) ctx.drafts.markSaved(CUSTOM_KEY, true);") > add.indexOf("await ctx.save("), "the key is marked stored only once the server is");
});

test("AI: Keys is one card per cloud provider with the check mark and Remove only when saved", () => {
  const ai = aiSrc();
  assert.ok(ai.includes("✓"));
  assert.ok(ai.includes('"check ok"') && ai.includes('"check bad"'));
  assert.match(ai, /classList\.toggle\("primary"/, "Save is primary only when dirty");
  assert.ok(ai.includes("From the Claude Console. Saved in your system's credential store, checked when you save."));
  assert.ok(ai.includes("From Google AI Studio. Saved in your system's credential store, checked when you save."));
  assert.ok(ai.includes("From the OpenAI dashboard. Saved in your system's credential store, checked when you save."));
});

test("AI: the Claude plan details keep today's words and the model select saves ai.claudeCodeModel", () => {
  const ai = aiSrc();
  for (const t of ['"Stop using it"', '"Use my Claude plan"', '"Sign in"', '"Check again"', '"How to install"', '"How to update"', '"Claude is now your main AI."', "NotchMeow never signs in to Claude and never reads Claude Code's credentials."]) {
    assert.ok(ai.includes(t), t);
  }
  assert.match(ai, /claudeCodeModel: /);
});

test("AI: the Local models help and the one-timer rule: no timers, no observers", () => {
  const ai = aiSrc();
  assert.ok(ai.includes("Models running on this computer, or on a server you add. Found automatically on this computer only."));
  assert.ok(ai.includes("unencrypted on your network"));
  assert.ok(ai.includes("Start the server and load a model first."));
  assert.doesNotMatch(ai, /setInterval|setTimeout|ResizeObserver|MutationObserver/);
});

test("AI: the old Preferred cloud select is gone from Your AI", () => {
  assert.doesNotMatch(aiSrc(), /Preferred cloud/);
});

test("app.ts: aiArrive runs on the chat place and on focus and visibility, the servers listener syncs, no timer", () => {
  assert.ok(count(app, "aiArrive(") >= 3, "the definition, the focus listener and the visibility listener");
  assert.match(app, /window\.addEventListener\("focus", \(\) => \{ away = false; shell\?\.fit\(\); void aiArrive\(\); \}\)/);
  assert.match(app, /visibilitychange[\s\S]{0,200}away = false;\s*shell\?\.fit\(\);\s*void aiArrive\(\)/);
  assert.doesNotMatch(app, /case "chat":\s*\n\s*void arrive\(\);/, "a chat tab no longer calls arrive on each build");
  assert.match(app, /if \(arrived\) void aiArrive\(\);/, "the arrival runs once, when the chat page opens");
  assert.match(app, /backend\.on<AiServer\[\]>\("ai-servers-changed"/);
  assert.match(app, /ai\.setServers\(s\) && chatOpen\) shell\?\.sync\(\)/);
  assert.doesNotMatch(app, /setInterval/);
});

test("ctx and devseed: the AI samples are in place (ready, empty, error, stress)", () => {
  const seed = read("src/settings/devseed.ts");
  assert.ok(seed.includes('"2.1.289"'), "Claude Code signed in at 2.1.289");
  assert.ok(seed.includes("claude-sonnet-5-5") && seed.includes("claude-haiku-5-5"));
  assert.ok(seed.includes("Studio PC") && seed.includes("http://192.168.1.20:11434"));
  assert.ok(seed.includes("LM Studio"));
  assert.ok(seed.includes("Studio PC in the back office (LM Studio)"), "the stress server name");
  assert.ok(seed.includes("needsGit: true"), "the error sample's Claude Code needs Git");
});

test("AI: Stop using it is one save of afterStopClaude, which also moves a Claude chat back to Auto, so Off and Main never share a row", () => {
  const stop = fnBody(aiSrc(), "async function stopClaude(", "  ");
  assert.equal(count(stop, "ctx.save("), 1, "one save");
  assert.match(stop, /ctx\.save\(\{ \.\.\.s, ai: Rows\.afterStopClaude\(s\.ai\) \}\)/);
  const rule = read("src/settings/airows.ts");
  assert.ok(rule.includes("export function afterStopClaude(ai: AiSettings): AiSettings {"));
  assert.ok(rule.includes('const chat = ai.chat !== "auto" && ai.chat.provider === "claudeCode" ? "auto" : ai.chat;'));
  assert.ok(rule.includes("return { ...ai, claudeCodeEnabled: false, preferredCloud: ai.preferredCloud === \"claudeCode\" ? \"anthropic\" : ai.preferredCloud, chat };"));
});

test("AI: the stale sign-in note is cleared by Use my Claude plan, Stop using it and Check again", () => {
  for (const marker of ["async function useClaude(", "async function stopClaude(", "async function checkClaude("]) {
    assert.match(fnBody(aiSrc(), marker, "  "), /signInNote = null;/, marker);
  }
});

// ── Sidekick and Cat (Settings restyle, Task 10) ──────────────────────────────

const sidekickSrc = read("src/settings/sidekick.ts");
const kitSrc = read("src/settings/kit.ts");
const catSrc = read("src/settings/cat.ts");
const displaySrc = read("src/settings/display.ts");
const wardrobeSrc = read("src/settings/wardrobe.ts");
const settingsCss = read("src/settings/settings.css");
const at = (text, needle) => {
  const i = text.indexOf(needle);
  assert.ok(i >= 0, `${needle} is there`);
  return i;
};

test("Sidekick: five cards in the brief's order", () => {
  const titles = ['card("Notes"', 'card("Quiet times"', 'card("Where its words come from"', 'card("Today so far"', 'card("Muted notes"'];
  const places = titles.map((t) => at(sidekickSrc, t));
  assert.deepEqual([...places].sort((a, b) => a - b), places);
});

test("Sidekick: the master switch is masterSwitch, writes withSidekickOn, and disables the kind rows while off", () => {
  assert.match(sidekickSrc, /const masterSwitch = switchRow\("Show notes from the sidekick"/);
  assert.match(sidekickSrc, /withSidekickOn\(/);
  assert.match(sidekickSrc, /masterSwitch\.set\(/);
  assert.match(sidekickSrc, /disabled: !s\.on/, "the kind rows follow the master");
});

test("Sidekick: Away recaps and Stuck nudges, the stuck switch is stuckSwitch's, and Choose which lists the four kinds by STUCK_NAMES", () => {
  assert.match(sidekickSrc, /switchRow\("Away recaps", \{[^}]*help: "A short recap when you come back and an agent did something\."/);
  assert.match(sidekickSrc, /switchRow\("Stuck nudges", \{[^}]*help: "A nudge when an agent looks stuck\."/);
  assert.match(sidekickSrc, /stuckSwitch\(/);
  assert.match(sidekickSrc, /details\("Choose which"/);
  assert.match(sidekickSrc, /STUCK_NAMES/);
  assert.match(sidekickSrc, /withMuted\(/);
  assert.match(sidekickSrc, /withUnmuted\(/);
});

test("Sidekick: the permission line is locked on, with no stored key", () => {
  assert.match(sidekickSrc, /switchRow\("Permission line", \{[^}]*on: true[^}]*disabled: true[^}]*help: PERMISSION_LINE/);
  assert.match(sidekickSrc, /switchRow\("Jokes and moods", \{[^}]*chip: COMES_WITH_F3A[^}]*disabled: true/);
});

test("Sidekick: Show me an example opens a st-example box inside the card, headed by the island's own words, drawn from example(kind)", () => {
  assert.ok(sidekickSrc.includes("Show me an example"));
  assert.ok(sidekickSrc.includes('"Claude Code · Welcome back"') && sidekickSrc.includes('"Claude Code · needs a look"'));
  assert.match(sidekickSrc, /example\(kind\)/, "the line is example(kind)");
  assert.match(sidekickSrc, /exampleControl\("recap"/);
  assert.match(sidekickSrc, /exampleControl\("stuck\.loop"/);
  assert.match(sidekickSrc, /st-example/);
  assert.doesNotMatch(sidekickSrc, /island\.|ledger|playSound|sound/i, "never the island, a sound or a ledger write");
});

test("Sidekick: Quiet times, Where its words come from and Today so far carry the F3a chip and the words", () => {
  assert.match(sidekickSrc, /card\("Quiet times", \{ summary: COMES_WITH_F3A \}/);
  for (const s of ["Full-screen apps", "Calls and screen sharing", "Chosen hours", "Coming soon: hold notes", "Until then notes never show over your work or while you type."]) assert.ok(sidekickSrc.includes(s), s);
  for (const s of ["Plain rules", "A model on this computer", "My main AI", "No local model found", "Found: ", "Only a model on this computer is ever asked"]) assert.ok(sidekickSrc.includes(s), s);
  assert.match(sidekickSrc, /type: "radio"/);
  assert.match(sidekickSrc, /NOTHING_LEAVES/);
  assert.match(sidekickSrc, /card\("Today so far", \{ summary: COMES_WITH_F3A \}/);
});

test("Sidekick: Muted notes lists each muted kind with Unmute, or says Nothing is muted, and keeps the dismiss line", () => {
  for (const s of ["Nothing is muted", "Unmute", "A note you dismiss twice is muted until you unmute it here."]) assert.ok(sidekickSrc.includes(s), s);
  assert.match(sidekickSrc, /button\("Unmute"/);
  assert.match(sidekickSrc, /row\(KIND_LABELS\[kind\], wrapRow\(unmute\)\)/, "the text button is in wrapRow, not row()");
});

test("Sidekick: no explain, timer or Bridge, and the switches are built once and set in place", () => {
  assert.doesNotMatch(sidekickSrc, /explain|setTimeout|setInterval|requestAnimationFrame|Bridge/);
  assert.doesNotMatch(sidekickSrc, /while \(el\.lastChild/);
  assert.match(kitSrc, /setAttribute\("aria-pressed", String\(on\)\)/);
});

test("Sidekick: the word radios write withLocal (plain is off, a model on this computer is on), and My main AI writes neither", () => {
  assert.match(sidekickSrc, /plain\.addEventListener\("change", \(\) => \{ if \(plain\.checked\) write\(withLocal\(host\.sidekick\(\), false\)\); \}\);/);
  assert.match(sidekickSrc, /local\.addEventListener\("change", \(\) => \{ if \(local\.checked\) write\(withLocal\(host\.sidekick\(\), true\)\); \}\);/);
  assert.doesNotMatch(sidekickSrc, /main\.addEventListener/, "the disabled My main AI radio has no listener");
  // The writer itself (sidekick/settings.ts) is pure: the two values it is called with give the two states.
  const off = withLocal(defaultSidekick(), false), on = withLocal(off, true);
  assert.equal(off.local, false);
  assert.equal(on.local, true);
});

test("Cat: each card sits in its own tab: Look, Personality and Agents' cats hold theirs, Outfits takes the Wardrobe card", () => {
  // Each tab's block is the `if (want("<tab>")) {` that encloses its own `groups.<tab>.push(`, cut to the close of that block (two spaces in). A card in another tab cannot satisfy it.
  const tabBlock = (tab) => {
    const push = catSrc.indexOf(`groups.${tab}.push(`);
    assert.ok(push >= 0, `groups.${tab}.push( exists`);
    const start = catSrc.lastIndexOf(`if (want("${tab}")) {`, push);
    assert.ok(start >= 0, `the if (want("${tab}")) block encloses its push`);
    return catSrc.slice(start, catSrc.indexOf("\n  }\n", start) + "\n  }\n".length);
  };
  const look = tabBlock("look");
  for (const c of ['card("Main cat"', 'card("Look"', 'card("Desktop"']) assert.ok(look.includes(c), `Look holds ${c}`);
  assert.doesNotMatch(look, /card\("(Personality|Motion|Every cat|Wardrobe)"/, "Look holds no card of another tab");
  const personality = tabBlock("personality");
  for (const c of ['card("Personality"', 'card("Motion"', 'card("Every cat"']) assert.ok(personality.includes(c), `Personality holds ${c}`);
  assert.doesNotMatch(personality, /card\("(Look|Main cat|Desktop|Display)"/, "Personality holds no card of another tab");
  // Outfits: the Wardrobe card is built by wardrobe.ts and pushed into the outfits group.
  assert.ok(wardrobeSrc.includes('card("Wardrobe"'), "the Wardrobe card is built in wardrobe.ts");
  assert.ok(catSrc.includes("groups.outfits.push(wardrobe.el)"), "the Outfits tab takes the Wardrobe card");
  // Agents' cats: the Display card, then the pair and the agents' cards, all pushed into that tab.
  const agentcats = catSrc.split("\n").find((l) => l.includes("groups.agentcats.push("));
  assert.ok(agentcats?.includes('card("Display", null, ...display.before), pairCard, agentsCard'), "Agents' cats holds Display, the pair and the agents' cards");
});

test("Cat: the tab type, catSection's tab argument, and the four tab values", () => {
  assert.match(catSrc, /export type CatTab = "look" \| "outfits" \| "personality" \| "agentcats";/);
  assert.match(catSrc, /export function catSection\(host: CatHost, tab: CatTab \| null = null\): \{ el: HTMLElement; sync\(\): void; dispose\(\): void \}/);
});

test("Cat: the loop stops at dispose: visible() checks !disposed, and the three listeners are named so dispose can remove them", () => {
  assert.match(catSrc, /visible: \(\) => drawing && !disposed &&/);
  for (const ev of ["visibilitychange", "focus", "blur"]) assert.match(catSrc, new RegExp(`removeEventListener\\("${ev}"`), ev);
  assert.match(catSrc, /const dispose = \(\): void => \{\s*disposed = true;[\s\S]*?loop\.sync\(\);/);
  assert.match(catSrc, /return \{ el, sync: paint, dispose \};/);
});

test("Cat: the cards of the tabs in tab order (Main cat, Look, Desktop, Wardrobe, Personality, Motion, Every cat, Display, Your two cats, Cats for your agents)", () => {
  const order = ['card("Main cat"', 'card("Look"', 'card("Desktop"', 'card("Personality"', 'card("Motion"', 'card("Every cat"', 'card("Display"'];
  const places = order.map((t) => at(catSrc, t));
  assert.deepEqual([...places].sort((a, b) => a - b), places);
  assert.match(wardrobeSrc, /card\("Wardrobe", null,/);
  assert.match(catSrc, /card\("Your two cats", null, \.\.\.display\.pair\)/);
  assert.match(catSrc, /card\("Cats for your agents", null, display\.agents\)/);
  assert.match(catSrc, /const TABS: readonly CatTab\[\] = \["look", "outfits", "personality", "agentcats"\];/, "the null tab gives the tabs in this order");
});

test("Cat: the Your two cats card shows only in Two cats mode and the agents card only in A cat for each agent", () => {
  assert.match(catSrc, /pairCard\.hidden = [^;]*displayMode !== "two"/);
  assert.match(catSrc, /agentsCard\.hidden = [^;]*displayMode !== "perAgent"/);
});

test("Cat: selects, ranges and the switch's state are written through setValue, never on the active element", () => {
  assert.ok(count(catSrc, "setValue(") >= 6, "motion, this cat's motion, collar, this cat's collar, preset and the six sliders");
  assert.doesNotMatch(catSrc, /\b(motion|collar|catMotion|catCollar|preset)\.value = /);
  assert.match(displaySrc, /setValue\(mode, /);
  assert.match(wardrobeSrc, /setValue\(picker, /);
});

test("Cat: the Cat CSS for narrow widths sits before the Wardrobe comment, and uses only tokens", () => {
  const wardrobeAt = at(settingsCss, "/* Wardrobe (sub-project I)");
  assert.match(settingsCss.slice(0, wardrobeAt), /\.cat-grid \{[^}]*grid-template-columns: repeat\(auto-fill, 56px\);[^}]*flex: 1 1 260px;/);
  assert.match(settingsCss.slice(0, wardrobeAt), /\.cat-notch canvas \{[^}]*max-width: 100%;[^}]*height: auto;/);
  assert.match(settingsCss.slice(0, wardrobeAt), /@media \(max-width: 599\.98px\) \{\s*\.row\.cat-trait \{[^}]*grid-template-areas:/);
});

test("app.ts builds the Sidekick tab and the four Cat tabs, not their placeholders", () => {
  assert.match(app, /case "sidekick": return sidekickSection\(/);
  assert.match(app, /catSection\(\{[\s\S]*?\}, \(place\.tab/);
  assert.doesNotMatch(app, /case "sidekick": return placeholder\(\)/);
  assert.doesNotMatch(app, /case "look": return placeholder\(\)/);
});

test("devseed: the Sidekick samples (ready, empty, error) and the Cat sample (perAgent, with a long agent name under stress)", () => {
  assert.ok(devseed.includes("stuck.errors") && devseed.includes("stuck.silent"), "ready mutes two stuck kinds");
  assert.ok(devseed.includes("qwen3.5:2b") && devseed.includes("aiLocalModel"), "the local model is found");
  assert.ok(devseed.includes('"perAgent"'), "the Cat sample is in the per-agent mode");
  assert.ok(devseed.includes("agent_a-rather-long-agent-name"), "stress adds the long agent name");
});

// ── Task 10, fix round 1 ───────────────────────────────────────────────────────

const mainSrc = read("src/settings/main.ts");

test("Task 10 fix: the switch knob and the range thumb have a 1 px edge in a token, so the light knob shows on the white card", () => {
  const block = (sel) => {
    const i = settingsCss.indexOf(`${sel} {`);
    assert.ok(i >= 0, sel);
    return settingsCss.slice(i, settingsCss.indexOf("}", i));
  };
  assert.match(block(".switch::after"), /box-shadow: 0 0 0 1px var\(--field-line\);/);
  assert.match(block('input[type="range"]::-webkit-slider-thumb'), /box-shadow: 0 0 0 1px var\(--field-line\);/);
  assert.doesNotMatch(settingsCss, /box-shadow:[^;]*#/, "no colour literal in a shadow");
});

test("Task 10 fix: the Wardrobe tiles are at least 104 px (the label needs about 100 px), with no fixed cell width, and no word is broken inside a word", () => {
  const w = settingsCss.slice(settingsCss.indexOf("/* Wardrobe (sub-project I)"));
  assert.match(w, /\.wardrobe-grid \{[^}]*grid-template-columns: repeat\(auto-fill, minmax\(104px, 1fr\)\);/);
  assert.match(w, /\.wardrobe-cell \{\s*width: auto;/);
  assert.doesNotMatch(w, /overflow-wrap: anywhere/, "no word is broken inside the Wardrobe labels");
  assert.doesNotMatch(w, /\.wardrobe-cell span \{[^}]*white-space: normal/, "the label stays on one line");
});

test("Task 10 fix: a tab's loop starts only when the tab built something to draw, and the dev shot flag counts as seen", () => {
  assert.match(catSrc, /const drawing = cells\.size > 0 \|\| preview !== null \|\| display !== null \|\| wardrobe !== null;/);
  assert.match(catSrc, /visible: \(\) => drawing && !disposed/);
  assert.match(catSrc, /document\.documentElement\.dataset\.shot === "1"/);
  assert.match(mainSrc, /if \(sample\) \{[\s\S]*?document\.documentElement\.dataset\.shot = "1";/, "set on the dev sample route only");
});

test("Task 10 fix: the Personality cards are built only for the Personality tab (and the null tab)", () => {
  assert.match(catSrc, /if \(want\("personality"\)\) \{/);
});

// ── Task 12: the swap ──────────────────────────────────────────────────────────
// The real window boots the shell: main.ts is the dev routes plus the start, app.ts listens to the window's events before its first await, and the page files carry no words of the old long page.

const appSrc = read("src/settings/app.ts");
const PAGE_FILES = ["general.ts", "agents.ts", "services.ts", "ai.ts", "sidekick.ts", "sidekicktab.ts", "cat.ts", "display.ts", "wardrobe.ts", "devices.ts"];

test("the swap: main.ts is under 80 lines (its DEV routes grew it), starts the shell through startSettingsApp and the bridge backend, and holds none of the old sections", () => {
  assert.ok(mainSrc.split("\n").length < 80, `${mainSrc.split("\n").length} lines`);
  assert.ok(mainSrc.includes("startSettingsApp("), "startSettingsApp(");
  assert.ok(mainSrc.includes("bridgeSettingsBackend("), "bridgeSettingsBackend(");
  for (const name of ["claudeSection", "agentHooksSection", "aiSection", "integrationsSection", "generalSection", "toggle", "statusDot", "renderDiff", "serverStatus", "choiceValue", "FEATURES", "INTEGRATIONS", "MAX_ACTIVE"]) {
    assert.doesNotMatch(mainSrc, new RegExp(`\\b${name}\\b`), name);
  }
  for (const words of ["Paste an API key", "Cloud providers", "Preferred cloud"]) assert.ok(!mainSrc.includes(words), words);
});

test("the swap: app.ts registers settings-place, settings-changed and settings-hidden before its first await", () => {
  const body = appSrc.slice(appSrc.indexOf("export async function startSettingsApp("), appSrc.indexOf("/** The page for a place"));
  const firstAwait = body.indexOf("await ");
  assert.ok(firstAwait > 0, "the boot awaits");
  for (const ev of ["settings-place", "settings-changed", "settings-hidden"]) {
    const at = body.indexOf(`"${ev}"`);
    assert.ok(at > 0 && at < firstAwait, `${ev} is registered before the first await`);
  }
});

test("the swap: settings-changed merges and tidies the settings and syncs the shell; the boot tidies them too", () => {
  assert.match(appSrc, /const tidy = \(s: Settings\): Settings => \(\{ \.\.\.s, cat: cleanCatBlock\(s\.cat\), sidekick: cleanSidekickSettings\(s\.sidekick\) \}\);/, "one clean-up, for the cat block and the sidekick object");
  assert.match(appSrc, /backend\.on<Partial<Settings>>\("settings-changed", \(s\) => \{\s*if \(!booted\) \{ early = \{ \.\.\.early, \.\.\.s \}; return; \}\s*settings = tidy\(\{ \.\.\.settings, \.\.\.s \}\);\s*saver\.echo\(tidyEcho\(s\)\);\s*shell\?\.sync\(\);\s*\}\);/);
  assert.match(appSrc, /const first = bootState\(boot, IS_TAURI\);\s*settings = tidy\(\{ \.\.\.first\.settings, \.\.\.early \}\);\s*booted = true;/, "the boot tidies the settings, and the changes received before it win");
  assert.match(appSrc, /desktopNote: boot && !boot\.desktopPositioned \? GNOME_NOTE : null/);
  assert.doesNotMatch(appSrc, /secretSet|markSaved/, "no handler saves a key or marks one saved");
});

test("the swap: settings-hidden clears the typed drafts, builds the page that holds typed text again (after the clear), and saves nothing", () => {
  const at = appSrc.indexOf('backend.on<unknown>("settings-hidden", () => {');
  assert.ok(at > 0, "the settings-hidden handler");
  const body = appSrc.slice(at, appSrc.indexOf("});", at));
  const clear = body.indexOf("drafts?.clearTyped();"), rebuild = body.indexOf("shell.select(place);");
  assert.ok(clear > 0, "clearTyped");
  assert.ok(rebuild > clear, "the page is built again after the clear, not only synced");
  assert.match(body, /holdsTypedText\(place\)/, "only a page that holds typed text is built again");
  assert.match(body, /else shell\?\.sync\(\);/, "the other pages are drawn as they are");
  assert.doesNotMatch(body, /secretSet|markSaved/, "the handler never saves a key or marks one saved");
  assert.match(appSrc, /if \(!chatOpen \|\| away\) return;/, "while hidden, the chat's refresh is held (nothing is looked for)");
  assert.match(appSrc, /window\.addEventListener\("focus", \(\) => \{ away = false; shell\?\.fit\(\); void aiArrive\(\); \}\);/, "shown again: the focus clears away, fits the tab bar and refreshes");
});

test("DraftBook.clearTyped: a typed field goes back to empty and not dirty, and a stored key stays saved", () => {
  const book = new DraftBook({ "openai-api-key": "present", "stripe-api-key": "absent" });
  book.edit("stripe-api-key", "sk_sample");
  book.edit("openai-api-key", "sk-sample-0000");
  assert.equal(book.isDirty("stripe-api-key"), true);
  book.clearTyped();
  assert.equal(book.text("stripe-api-key"), "");
  assert.equal(book.isDirty("stripe-api-key"), false, "the Not saved chip goes with the text");
  assert.equal(book.anyDirty(["openai-api-key", "stripe-api-key"]), false, "Save is disabled again");
  assert.equal(book.isSaved("openai-api-key"), true, "a stored key stays stored");
});

test("holdsTypedText: the services page and the chat's keys and local-models tabs hold typed text; the other places do not", () => {
  for (const place of [{ page: "services", tab: null }, { page: "chat", tab: "keys" }, { page: "chat", tab: "localmodels" }]) assert.equal(holdsTypedText(place), true, JSON.stringify(place));
  for (const place of [{ page: "general", tab: null }, { page: "agents", tab: null }, { page: "devices", tab: null }, { page: "cat", tab: "look" }, { page: "chat", tab: "yourai" }, { page: "chat", tab: "sidekick" }]) assert.equal(holdsTypedText(place), false, JSON.stringify(place));
});

test("the swap: no page file names the Shortcuts tab, codex or Plan usage", () => {
  for (const f of PAGE_FILES) {
    const text = read(`src/settings/${f}`);
    assert.doesNotMatch(text, /Shortcuts/, f);
    assert.doesNotMatch(text, /\bcodex\b/, f);
    assert.doesNotMatch(text, /Plan usage/, f);
  }
});

test("the swap: no Settings text names the old per-agent sections by their arrow path", () => {
  const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(new URL(`${e.name}/`, dir)) : [new URL(e.name, dir)]));
  for (const f of walk(new URL("../../src/", import.meta.url))) {
    if (!f.pathname.endsWith(".ts")) continue;
    assert.doesNotMatch(fs.readFileSync(f, "utf8"), /Settings… → (Claude Code|Gemini CLI|Antigravity|AI\b)/, f.pathname);
  }
});

// ── Settings restyle fix wave (final review: I1, I2, M1, M4, M5, M6, M7, M8; G3, G4, G6, B1, B3, B4, B6, B8, B10) ──

const shellSrc = read("src/settings/shell.ts");
const backendSrc = read("src/settings/backend.ts");
const airowsSrc = read("src/settings/airows.ts");

test("app.ts: the window is away until it is focused (away starts from document.hasFocus()), and its three resets and one hide stay", () => {
  assert.match(app, /let away = !document\.hasFocus\(\) && document\.documentElement\.dataset\.shot !== "1";/);
  assert.doesNotMatch(app, /let away = false;/);
  assert.equal(count(app, "away = false;"), 4, "settings-place, focus, visibility and the first press or key clear it");
  assert.equal(count(app, "away = true;"), 1, "settings-hidden sets it");
});

test("app.ts: the real window stays away until focused; the dev sample's shot flag is the only exception, and only the sample route sets it", () => {
  // The focus term is still the first operand: a real window that has no focus is away, whatever the flag says.
  assert.match(app, /let away = !document\.hasFocus\(\) && /, "the focus term is still first");
  assert.equal(count(mainSrc, 'dataset.shot = "1"'), 1, "main.ts sets it once");
  const sampleAt = mainSrc.indexOf("if (sample) {");
  const setAt = mainSrc.indexOf('document.documentElement.dataset.shot = "1";');
  assert.ok(sampleAt > 0 && setAt > sampleAt, "the one assignment is inside the sample branch");
  assert.ok(setAt < mainSrc.indexOf("return;", sampleAt), "and before the sample branch returns");
  for (const f of ["app.ts", "shell.ts", "devices.ts", "agents.ts", "ai.ts", "general.ts", "cat.ts", "kit.ts"]) {
    assert.doesNotMatch(read(`src/settings/${f}`), /dataset\.shot\s*=(?!=)/, `${f} never sets the flag (a comparison with === does not count)`);
  }
});

test("app.ts: a place that lands on a chat page already open runs the arrival again (no focus event came), and the flag is cleared first", () => {
  const at = app.indexOf('backend.on<string>("settings-place", (p) => {');
  assert.ok(at > 0, "the settings-place handler exists");
  const body = app.slice(at, app.indexOf("});", at));
  assert.match(body, /away = false;/, "the place still clears away");
  assert.match(body, /const chatWasOpen = chatOpen;/);
  assert.match(body, /if \(shell && !alreadyShown\(pending, shell\.current\(\)\)\) shell\.select\(pending\);\s*\n(?:\s*\/\/[^\n]*\n)*\s*if \(chatWasOpen && chatOpen\) void aiArrive\(\);/, "after the select, and only for a chat that stays open");
  assert.match(app, /let chatOpen = false;/, "chatOpen is declared before the first await, so an early event cannot reach it in its dead zone");
  assert.equal(count(app, "let chatOpen = false;"), 1, "declared once");
});

test("app.ts: settings-hidden sets away before it builds the page again", () => {
  const at = app.indexOf('backend.on<unknown>("settings-hidden", () => {');
  assert.ok(at > 0, "the handler exists");
  const body = app.slice(at, app.indexOf("});", at));
  assert.ok(body.indexOf("away = true;") >= 0, "away is set");
  assert.ok(body.indexOf("away = true;") < body.indexOf("shell.select(place);"), "away is set before the rebuild");
});

test("app.ts: the chat's arrival runs when the chat page opens, not on each chat tab, and the placeholder is gone", () => {
  assert.match(app, /const arrived = place\.page === "chat" && !chatOpen;/);
  assert.match(app, /chatOpen = place\.page === "chat";\s*\n\s*if \(arrived\) void aiArrive\(\);/);
  assert.doesNotMatch(app, /placeholder/);
  assert.match(app, /default: return yourAiTab\(ctx, CLOUD_PROVIDERS\);/, "every other chat tab is drawn as Your AI");
  assert.match(app, /case "companion": return companionTab\(\{/, "the Companion tab is drawn by companionTab, before the default");
  assert.match(app, /switch \(place\.page\)/, "one switch on the page");
});

test("app.ts: a settings change received before the boot snapshot is kept and wins over it", () => {
  assert.match(app, /let early: Partial<Settings> = \{\};/);
  assert.match(app, /if \(!booted\) \{ early = \{ \.\.\.early, \.\.\.s \}; return; \}/);
  assert.match(app, /settings = tidy\(\{ \.\.\.first\.settings, \.\.\.early \}\);\s*\n\s*booted = true;/);
});

test("Devices: a window never shown does not open the pairing gate, and a later blur keeps it open (the shown flag)", () => {
  // Until the window has been focused once, "open" needs focus; after that the gate follows inView and the page's visibility only, as the old page did.
  assert.ok(devices.includes("let shown = false;"), "shown starts false");
  assert.match(devices, /const open = inView && !document\.hidden && \(shown \|\| document\.hasFocus\(\)\);/);
  assert.match(devices, /const onFocus = \(\) => \{ shown = true; said = null; report\(\); \};/, "the first focus sets shown and re-reports");
  assert.match(devices, /const onVisibility = \(\) => \{\s*if \(document\.visibilityState === "visible" && document\.hasFocus\(\)\) shown = true;\s*report\(\);\s*\};/, "a visible page that has focus also sets shown");
  // A page that is open because of focus (not yet shown) counts as shown from then on: report() sets shown before it compares, so a later blur keeps the gate open.
  assert.match(devices, /const open = inView && !document\.hidden && \(shown \|\| document\.hasFocus\(\)\);/);
  assert.match(devices, /if \(open && document\.hasFocus\(\)\) shown = true;\s*\n\s*if \(open === said\) return;/, "report() sets shown when the open decision relies on focus, before the comparison");
  assert.doesNotMatch(devices, /window\.addEventListener\("blur"|onblur/, "a window blur is not a reason to close the gate (the name field's own blur is unrelated)");
  assert.ok(devices.includes('window.addEventListener("focus", onFocus)'), "the focus handler re-reports when the window is shown");
  const dispose = devices.slice(devices.lastIndexOf("dispose() {"), devices.indexOf("\n    },", devices.lastIndexOf("dispose() {")));
  assert.match(dispose, /removeEventListener\("visibilitychange"/);
  assert.match(dispose, /removeEventListener\("focus"/);
  assert.match(dispose, /removeEventListener\("pagehide", onHide\)/);
  assert.match(dispose, /backend\.setDevicesOpen\(false\)/);
});

test("Agents: until the first hook read lands the card says Checking, with no missing-hooks notice or chip", () => {
  assert.doesNotMatch(agents, /NO_STATUS/);
  assert.ok(agents.includes('"Checking…"'));
  assert.match(agents, /if \(status\) \{[\s\S]*if \(!status\.hookReady\) \{\s*const file/, "the relay notice needs a read");
  assert.match(agents, /const checking = kind !== undefined && !hooks\.has\(kind\);/);
  assert.match(agents, /checking \|\| installed \? null : "Hooks not installed"/);
});

test("Agents: a hook read that fails says so with one Check again (not primary, no timer); Checking… only while the read is in flight; Install stays disabled", () => {
  // In flight: the failed mark is cleared and the card paints Checking… again (Check again's own read).
  assert.match(agents, /const failed = new Set<HookKind>\(\);/);
  const refreshAt = agents.indexOf("const refresh = async (kind: HookKind): Promise<void> => {");
  assert.ok(refreshAt > 0, "refresh exists");
  assert.match(agents.slice(refreshAt, agents.indexOf("const fresh", refreshAt)), /failed\.delete\(kind\);\s*\n\s*paintCard\(kind\);/, "a read starts by clearing the failed mark and painting Checking…");
  assert.match(agents, /const fresh = await readStatus\(kind\)\.catch\(\(\) => undefined\);/, "a rejected read is a failed read, not a stuck card");
  assert.match(agents, /if \(fresh\) hooks\.set\(kind, fresh\);\s*\n\s*else if \(!hooks\.has\(kind\)\) failed\.add\(kind\);/, "a failed read with no status held is marked failed; a held status stays");
  assert.match(agents, /hookCard\(ctx, kind, hooks\.get\(kind\) \?\? null, failed\.has\(kind\), \(\) => void refresh\(kind\)\)/);
  assert.ok(agents.includes("Couldn't read the hook status."), "the plain line");
  assert.match(agents, /help\("Couldn't read the hook status\."\),\s*\n\s*wrapRow\(button\("Check again", refreshLater\)\)/, "one Check again, in a wrapRow, not primary");
  assert.doesNotMatch(agents, /button\("Check again", refreshLater, "primary"\)/);
  assert.equal(count(agents, "setTimeout("), 1, "the only timer is the 2.6 s one after a write");
  assert.match(agents, /install\.title = broken \? \(claude \? "settings\.json couldn't be read\." : "The config file couldn't be read\."\) : status \? "The relay isn't installed yet\." : failed \? "The hook status couldn't be read\." : "Checking the hooks first\.";/, "Install is disabled while in flight and after a failed read");
  assert.match(agents, /if \(!status \|\| !status\.hookReady \|\| broken\) \{\s*\n\s*install\.disabled = true;/);
});

test("Agents: settings.json that cannot be read says so on the card (Couldn't read, the fixed words), never Not installed; Check again and Install is off", () => {
  assert.match(agents, /const broken = Boolean\(status\?\.error\);/);
  assert.match(agents, /help\(broken \? unusableHelp\(claude, status\.reason\) : status\.installed/, "the words of the read error and its reason replace the installed or not line");
  assert.match(agents, /if \(broken\) body\.append\(wrapRow\(button\("Check again", refreshLater\)\)\);/, "Check again is offered once for a broken file");
  assert.match(agents, /install\.title = broken \? \(claude \? "settings\.json couldn't be read\." : "The config file couldn't be read\."\) :/, "Install says why it is off, per kind");
  assert.match(agents, /help\(broken \? unusableHelp\(claude, status\.reason\)/, "the kind picks settings.json or the config file inside the helper");
  const agentRust = read("src-tauri/src/agent_hooks.rs");
  assert.ok(agentRust.includes('UNREADABLE_CONFIG: &str = "Couldn\'t read the config file."'), "the agents' status sends the same sentence");
  assert.ok(agents.includes("unusableHelp"), "the agents' words come from status.ts");
  const rust = read("src-tauri/src/hooks.rs");
  assert.ok(rust.includes('UNREADABLE_SETTINGS: &str = "Couldn\'t read settings.json."'), "the Rust status sends the same sentence");
});

test("Agents: a Claude Code write says the file was created when there was none, and names the backup only when one was kept", () => {
  assert.match(agents, /claudeBackupNote\(saved, \(path\) => displayPath\(path, ctx\.home\)\)/);
  const rust = read("src-tauri/src/hooks.rs");
  assert.match(rust, /Ok\(if existed \{ backup\.to_string_lossy\(\)\.to_string\(\) \} else \{ String::new\(\) \}\)/, "write returns the backup only when one was made");
  assert.match(rust, /backup: if settings_path\(\)\.exists\(\) \{/, "the preview names no backup for a missing file");
});

test("AI: Claude Code's status is Checking until the first read, and says Couldn't check once a read has landed with no answer; the install link waits for the answer", () => {
  const ai = aiSrc();
  assert.ok(ai.includes('if (c === null) return read ? "Couldn\'t check Claude Code." : "Checking…";'));
  assert.match(ai, /\} else if \(c !== null\) \{\s*actions\.push\(h\("a", \{/);
  assert.match(ai, /actions\.push\(button\("Check again", \(\) => void checkClaude\(\)\)\);/, "Check again is always there, so a failed read can be read again");
  assert.match(ai, /return \{ sig: JSON\.stringify\(\[c, inUse, signInNote, ctx\.ai\.claudeRead\]\), build: \(\) => claudeNodes\(c, inUse, ctx\.ai\.claudeRead\) \};/, "the row repaints when the read lands, even with no answer");
  assert.match(ai, /try \{\s*\n\s*ctx\.ai\.claude = \(await ctx\.backend\.claudeStatus\(\)\) \?\? null;[\s\S]*?ctx\.ai\.claudeRead = true;/, "Check again marks the read done, after its own try");
  const cache = read("src/settings/aicache.ts");
  assert.match(cache, /claudeRead = false;/);
  assert.match(cache, /this\.claude = \(await this\.backend\.claudeStatus\(\)\) \?\? null;\s*\n\s*\} catch \{\s*\n\s*this\.claude = null;\s*\n\s*\}\s*\n\s*this\.claudeRead = true;/, "the refresh marks the read done, whatever it said, and a rejected read is caught");
});

test("Local models: a repaint waits while the focus is in the Add server form, the blur repaints, and the actions repaint directly", () => {
  const ai = aiSrc();
  const lm = ai.slice(ai.indexOf("export function localModelsTab("));
  assert.match(lm, /function sync\(\): void \{\s*if \(body\.contains\(document\.activeElement\)\) return;\s*paint\(\);/);
  assert.match(lm, /body\.addEventListener\("focusout"/);
  assert.equal(count(lm, "sync();"), 0, "the actions do not go through the guarded sync");
});

test("main.ts and shell.ts: a start-up failure is logged and shown, and a page that will not build is one card with the shell kept consistent", () => {
  assert.match(mainSrc, /void main\(\)\.catch\(\(err: unknown\) => \{/);
  assert.ok(mainSrc.includes("Settings couldn't start. Close and reopen this window."));
  assert.ok(mainSrc.includes("console.error("));
  const sel = shellSrc.slice(shellSrc.indexOf("function select(place: Place)"), shellSrc.indexOf("// One listener for the window"));
  assert.ok(sel.indexOf("view?.dispose?.();") < sel.indexOf("try {"), "dispose, then build (the Devices gate and the Cat loop rely on it)");
  assert.match(sel, /try \{\s*view = o\.build\(current\);\s*\} catch \(err\) \{/);
  assert.match(sel, /console\.error\(/);
  assert.ok(sel.includes("This page couldn't be drawn."));
});

test("Copy reports what happened: copyText says whether the clipboard took it, and Copy says so until the paths are shown or hidden (no timer)", () => {
  assert.match(backendSrc, /copyText\(text: string\): Promise<boolean>;/);
  assert.match(backendSrc, /copyText: async \(text\) => \(await Bridge\.copyText\(text\)\) === true,/);
  assert.match(kitSrc, /copy: \(text: string\) => Promise<boolean>/);
  assert.ok(kitSrc.includes('"Copied"') && kitSrc.includes("\"Couldn't copy\""));
  assert.match(kitSrc, /for \(const c of copies\) c\.textContent = "Copy";/);
  assert.doesNotMatch(kitSrc, /setTimeout/);
});

test("the Settings listeners log a failed registration instead of dropping it", () => {
  assert.doesNotMatch(backendSrc, /void onEvent/);
  assert.match(backendSrc, /onEvent<T>\(event, handler\)\.catch\(\(err: unknown\) => console\.error\(/);
});

test("Services: a pill switch is written through nextActive, the one cap rule, and the card's pill state comes from pillSwitch", () => {
  assert.ok(services.includes("nextActive(s.activeIntegrations, id, on)"));
  assert.ok(services.includes("pillSwitch(on, false, active.length, null)"));
  assert.doesNotMatch(services, /MAX_SLOTS/);
  assert.match(read("src/settings/status.ts"), /export function nextActive\(/);
});

test("Services: a write marks a field saved only after it is awaited; a refused write returns before the ok notice; a removal marks after its awaited clear", () => {
  const save = services.slice(services.indexOf("async function saveAll()"), services.indexOf("async function removeKey("));
  const catchAt = save.indexOf("catch");
  const marked = save.indexOf("markSaved(id, true, typed)");
  assert.ok(marked >= 0, "the success path marks the field saved");
  assert.ok(marked < catchAt, "marked on the success path, before the catch");
  const saveCatch = save.slice(catchAt, save.indexOf("        }", catchAt));
  assert.ok(saveCatch.includes("return;"), "the catch returns");
  assert.ok(!saveCatch.includes("markSaved"), "the catch never marks the field saved");
  assert.ok(save.indexOf('notice("ok"') > catchAt + saveCatch.length, "the ok notice comes after the catch");

  const remove = services.slice(services.indexOf("async function removeKey("), services.indexOf("for (const f of def.fields) {\n      const present"));
  const rc = remove.indexOf("catch");
  const removeCatch = remove.slice(rc, remove.indexOf("\n      }", rc));
  assert.ok(removeCatch.includes("return;"), "the removal's catch returns");
  assert.ok(!removeCatch.includes("markSaved"), "the removal's catch marks nothing");
  assert.ok(remove.indexOf("await ctx.backend.secretClear(") < rc, "the clear is awaited before the catch");
  assert.ok(remove.indexOf("markSaved(f.key, false)") > remove.indexOf("\n      }", rc), "the mark comes after the try, outside the catch");
});

test("holdsTypedText covers every settings file that draws a key field, so a new keyField page cannot forget the drop-on-hide rule", () => {
  const dir = new URL("../../src/settings/", import.meta.url);
  // kit.ts defines keyField; every other file that calls it is listed with the places whose typed text a hide forgets.
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".ts") && f !== "kit.ts" && fs.readFileSync(new URL(f, dir), "utf8").includes("keyField("));
  const places = {
    "services.ts": [{ page: "services", tab: null }],
    "ai.ts": [{ page: "chat", tab: "keys" }, { page: "chat", tab: "localmodels" }],
  };
  assert.deepEqual(files.sort(), Object.keys(places).sort(), "the files that draw a key field are the ones listed here");
  for (const list of Object.values(places)) for (const p of list) assert.ok(holdsTypedText(p), JSON.stringify(p));
});

test("airows: the stop and use rules are pure functions in airows.ts, and ai.ts's stopClaude and useClaude call them", () => {
  assert.match(airowsSrc, /export function afterStopClaude\(ai: AiSettings\): AiSettings \{/);
  assert.match(airowsSrc, /export function afterUseClaude\(ai: AiSettings\): AiSettings \{/);
  assert.match(aiSrc(), /ai: Rows\.afterUseClaude\(s\.ai\)/);
});

test("backend.ts: the bridge's claudeStatus never rejects (a failed read is undefined), so the Claude row can say it could not check", () => {
  assert.match(backendSrc, /claudeStatus: async \(\) => \(await Bridge\.claudeStatus\(\)\.catch\(\(\) => undefined\)\) \?\? undefined,/);
});

test("main.ts: the lines outside the DEV sample branch (comments and the shot branch included) stay under 50, so the entry stays thin whatever the dev routes add", () => {
  const lines = mainSrc.split("\n");
  const start = lines.indexOf("  if (sample) {");
  assert.ok(start > 0, "the sample branch is there to step over");
  let end = start + 1;
  while (end < lines.length && lines[end] !== "  }") end++;
  assert.ok(end < lines.length, "the sample branch closes at its own indent");
  const production = [...lines.slice(0, start), ...lines.slice(end + 1)];
  assert.ok(production.length < 50, `${production.length} lines outside the sample branch`);
});

// ── Companion (F3a-tauri, Task 12) ─────────────────────────────────────────────

const companionSrc = read("src/settings/companion.ts");
// The words the tab shows: the tab's own file and the pure rules beside it (the sentence "Nothing sent…" lives in the rules).
const companionWords = companionSrc + read("src/settings/companionrules.ts");

test("Companion: the tab is shown and its title is Companion", () => {
  assert.equal(tabTitle("companion"), "Companion");
  assert.equal(tabs("chat").at(-1), "companion");
});

test("Companion: the four cards in the Mac's order: Personality, What the chat knows, Conversations, What the AI saw last", () => {
  const at = ["Personality", "What the chat knows", "Conversations", "What the AI saw last"].map((t) => companionSrc.indexOf(`card("${t}"`));
  assert.ok(at.every((i) => i >= 0), "the four card calls exist");
  assert.ok(at[0] < at[1] && at[1] < at[2] && at[2] < at[3], "in the Mac's order");
});

test("Companion: the Mac's words are on the page, with this Mac read as this computer (the Swift side is drift.test.mjs)", () => {
  for (const w of [
    "Off", "A little", "More", "Humor", "See my sessions", "Delete all…", "Show", "Done", "Delete all", "Cancel",
    "The cat's traits come from Cat → Personality. While an agent waits for you, it makes no jokes.",
    "Project names and what your Claude Code sessions are doing, never a path or what was written.",
    "Kept on this computer, 50 at most; the oldest unpinned goes first.",
    "Kept in memory only, gone when NotchMeow quits.",
    "What the AI saw last", "Nothing sent since NotchMeow started.",
    "Delete all saved conversations?",
    "Every saved conversation on this computer is deleted. This cannot be undone.",
  ]) assert.ok(companionWords.includes(w), w);
});

test("Companion: the page writes only companion.humor and companion.seeSessions, through a spread of the whole block", () => {
  assert.match(companionSrc, /write\(\{ humor: /);
  assert.match(companionSrc, /write\(\{ seeSessions: /);
  assert.match(companionSrc, /o\.put\(\{ \.\.\.o\.settings\(\), \.\.\.patch \}\)/, "the spread keeps cloudNoticeShown");
  for (const k of ["cloudNoticeShown", "useMemory", "polishRecap", "recapDismissals", "lastRecapDay"]) assert.doesNotMatch(companionSrc, new RegExp(k), k);
});

test("Companion: the brain line comes from sentTo (the chrome's words), and the brain name from the chat's resolution", () => {
  assert.match(companionSrc, /import \{ sentTo \} from "\.\.\/companion\/chrome\.ts";/);
  assert.equal(brainNameOf(undefined), "your AI");
  assert.equal(brainNameOf({ empty: true, auto: false, provider: null, model: null, placement: null, modelName: null, reader: null, fallback: null }), "your AI");
  assert.equal(brainNameOf({ empty: false, auto: true, provider: "local", model: "qwen3.5:2b", placement: "local", modelName: "qwen3.5:2b", reader: null, fallback: null }), "Auto · qwen3.5:2b", "Auto keeps the chat chip's prefix");
  assert.equal(brainNameOf({ empty: false, auto: false, provider: "local", model: "qwen3.5:2b", placement: "local", modelName: "qwen3.5:2b", reader: null, fallback: null }), "qwen3.5:2b");
  assert.equal(brainNameOf({ empty: false, auto: false, provider: "anthropic", model: null, placement: "cloud", modelName: null, reader: null, fallback: null }), "your AI", "a provider id is never shown as the brain");
  assert.equal(brainNameOf({ empty: false, auto: false, provider: "claudeCode", model: "sonnet", placement: "claudeCode", modelName: "Sonnet", reader: null, fallback: null }, "claude.ai"), "Claude · your plan", "Claude Code reads the chat chip's words");
});

test("Companion: Delete all asks first behind an inline confirm with Cancel, and the Show box is read-only and selectable", () => {
  assert.match(companionSrc, /button\("Delete all…"/);
  assert.match(companionSrc, /button\("Delete all", /);
  assert.match(companionSrc, /button\("Cancel"/);
  assert.match(companionSrc, /h\("pre"/, "the saw box is a pre: read-only text");
  assert.match(companionWords, /Nothing sent since NotchMeow started\./);
  assert.doesNotMatch(companionSrc, /contenteditable|<textarea|h\("textarea"|h\("input"/, "nothing in the Companion tab is typed into");
});

test("Companion: a failed Delete all says so under the count, in the chat pane's words (Couldn't delete the conversations.)", () => {
  assert.match(companionSrc, /deleteAll\(\)\.then\(\(ok\) =>/, "the result is read");
  assert.ok(companionSrc.includes("Couldn't delete the conversations."), "the one-line note");
});

test("Companion: a Delete all that works empties and hides the shown What the AI saw last box (no DOM under node: a source pin)", () => {
  assert.match(companionSrc, /if \(ok\) \{\s*sawBox\.hidden = true;\s*saw\.textContent = "";\s*\}/, "a succeeded delete clears the shown lines");
});
