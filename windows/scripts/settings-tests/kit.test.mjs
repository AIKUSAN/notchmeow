// Pins for the Settings layout kit, the shell, the app and the dev routes (Task 5 of the Windows and Linux Settings restyle). They read the source as text, because Node has no
// DOM: the rules the spec and the brief state are held here, and the pictures (windows/scripts/render-settings.sh) show the rest. Layout numbers are the layout.ts constants.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { fnText, anyFnText, sliceBetween } from "./slice.mjs";
import { BREAKPOINT, SIDEBAR_WIDE, SIDEBAR_ICONS, COLUMN_MAX, PADDING, PADDING_COLLAPSED, FIELD_MAX, NUMBER_FIELD, PICKER_WIDTH, HELP_SIZE, TAB_BAR_HEIGHT } from "../../src/settings/layout.ts";

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const SETTINGS = "src/settings/";
const kit = read(`${SETTINGS}kit.ts`);
const shell = read(`${SETTINGS}shell.ts`);
const app = read(`${SETTINGS}app.ts`);
const backend = read(`${SETTINGS}backend.ts`);
const ctx = read(`${SETTINGS}ctx.ts`);
const main = read("src/settings/main.ts");
const css = read(`${SETTINGS}settings.css`);
const catDev = read("src/cat/dev.ts");
const script = read("scripts/render-settings.sh");

/** The Settings block of the style sheet: from its comment to the Wardrobe comment that ends the old sheet. */
function settingsBlock() {
  const start = css.indexOf("/* Settings restyle");
  const end = css.indexOf("/* Wardrobe (sub-project I)");
  assert.ok(start > 0 && end > start, "the Settings restyle block sits before the Wardrobe comment");
  return css.slice(start, end);
}

test("kit.ts exports every function the brief names", () => {
  for (const name of ["card", "row", "switchRow", "keyField", "chip", "wrapRow", "pathDisclosure", "help", "notice", "button", "select", "setValue", "details", "renderDiff", "tabBar"]) {
    assert.match(kit, new RegExp(`export function ${name}\\(`), name);
  }
  assert.match(kit, /export interface SwitchRow \{ el: HTMLElement; set\(/);
});

test("tabBar measures the row against its width and offers a select, never a segmented control", () => {
  const fn = fnText(kit, "tabBar");
  assert.ok(fn.includes("scrollWidth > "), "tabBar compares scrollWidth with the row");
  assert.ok(fn.includes("clientWidth"), "tabBar reads clientWidth");
  assert.match(fn, /const menu = select\(list\.map/, "tabBar builds its pop-up menu with the select helper");
  assert.match(fnText(kit, "select"), /h\("select"/, "the select helper makes a select element");
  assert.doesNotMatch(kit, /segmented/i);
});

test("setValue writes a value only when the field is not being typed in", () => {
  assert.match(fnText(kit, "setValue"), /document\.activeElement/);
});

test("switchRow updates aria-pressed in place with setAttribute", () => {
  assert.ok(kit.includes('setAttribute("aria-pressed", String('), "aria-pressed is set with setAttribute(String(...))");
});

test("the shell disposes the old view before it builds the next, and migrates and remembers the places", () => {
  // Sliced to select()'s body: a comment or another function's word cannot satisfy the order.
  const select = sliceBetween(shell, "function select(place: Place): void {", "\n  }\n");
  const dispose = select.indexOf("view?.dispose?.()");
  const build = select.indexOf("o.build(");
  assert.ok(dispose > 0 && build > dispose, "dispose() comes before o.build() inside select()");
  assert.ok(shell.includes("migrate("), "the shell migrates stored sections");
  assert.ok(shell.includes("placeWithStored("), "the shell settles a bare place on the stored tab");
});

test("the shell wraps every storage read and write in try", () => {
  assert.match(shell, /try\s*\{[^}]*getItem/, "getItem is wrapped in try");
  assert.match(shell, /try\s*\{[^}]*setItem/, "setItem is wrapped in try");
});

test("the shell listens to resize once and fits the tab bar through requestAnimationFrame", () => {
  assert.equal([...shell.matchAll(/addEventListener\("resize"/g)].length, 1, "one resize listener");
  assert.ok(shell.includes("requestAnimationFrame"), "the resize fit is one animation frame");
});

test("app.ts registers the settings-place listener before its first await", () => {
  // Sliced to startSettingsApp's body, with the comments taken out: a comment that says "await" cannot move the first await.
  const body = sliceBetween(app, "export async function startSettingsApp(", "\n}\n").replace(/\/\/[^\n]*/g, "");
  const place = body.indexOf('backend.on<string>("settings-place"');
  const firstAwait = body.indexOf("await ");
  assert.ok(place > 0, "settings-place is registered in startSettingsApp");
  assert.ok(firstAwait < 0 || place < firstAwait, "the listener is registered before any await");
});

test("app.ts reads a settings-place through placeOrCurrent against the open page, so an unknown page keeps the page on screen", () => {
  const handler = sliceBetween(app, 'backend.on<string>("settings-place", (p) => {', "\n  });\n");
  assert.ok(handler.includes("placeOrCurrent(p, shell.current())"), "the place is placeOrCurrent(p, the shell's current place)");
});

test("no timer or observer in kit, shell or app: the rules are event-driven", () => {
  for (const [name, text] of [["kit.ts", kit], ["shell.ts", shell], ["app.ts", app]]) {
    assert.doesNotMatch(text, /setInterval|setTimeout|ResizeObserver|MutationObserver/, name);
  }
});

test("only backend.ts touches the Bridge in the Settings folder", () => {
  const dir = new URL(`../../${SETTINGS}`, import.meta.url);
  const hits = fs.readdirSync(dir).filter((f) => f.endsWith(".ts") && fs.readFileSync(new URL(f, dir), "utf8").includes("Bridge."));
  assert.deepEqual(hits.sort(), ["backend.ts"]);
});

test("backend.ts exposes the SettingsBackend the brief names, with on<T> and bridgeSettingsBackend", () => {
  assert.match(backend, /export interface SettingsBackend \{/);
  for (const m of ["boot", "save", "hooksStatus", "hooksPreview", "hooksApply", "agentHooksStatus", "agentHooksPreview", "agentHooksApply", "secretPresence", "secretSet",
    "secretClear", "aiListModels", "aiDiscover", "aiResolve", "claudeStatus", "claudeSignIn", "aiLocalModel", "openUrl", "copyText"]) {
    assert.match(backend, new RegExp(`\\n  ${m}\\(`), m);
  }
  assert.match(backend, /on<T>\(event: "settings-changed" \| "ai-servers-changed" \| "settings-place" \| "settings-hidden"/);
  assert.match(backend, /export function bridgeSettingsBackend\(link: LinkBackend\): SettingsBackend/);
});

test("ctx.ts holds SettingsCtx as the brief has it (Task 9 adds ai)", () => {
  const block = /export interface SettingsCtx \{[\s\S]*?\n\}/.exec(ctx);
  assert.ok(block, "SettingsCtx is exported");
  for (const field of ["backend: SettingsBackend", "settings(): Settings", "save(next: Settings): Promise<boolean>", "home: string", "drafts: DraftBook", "open(place: Place): void", "platform: Platform", "desktopNote: string | null"]) {
    assert.ok(block[0].includes(field), field);
  }
  assert.match(block[0], /ai: AiCache;/, "the AI cache is the one field Task 9 adds");
  assert.match(ctx, /export interface PageView \{ el: HTMLElement; sync\?\(\): void; dispose\?\(\): void \}/);
});

test("the Settings restyle block adds no colour literal: only the tokens of :root", () => {
  const block = settingsBlock();
  assert.doesNotMatch(block, /#[0-9a-fA-F]{3,8}\b/, "no hex colour");
  assert.doesNotMatch(block, /rgba?\(/, "no rgb() colour");
});

test("the Settings restyle block comes before the Wardrobe comment, and every :root block comes before it too", () => {
  const wardrobe = css.indexOf("/* Wardrobe (sub-project I)");
  assert.ok(css.indexOf("/* Settings restyle") < wardrobe, "the block precedes the Wardrobe comment");
  for (const m of css.matchAll(/:root \{/g)) assert.ok(m.index < wardrobe, ":root before the Wardrobe comment");
});

test("the CSS numbers equal layout.ts's constants", () => {
  const block = settingsBlock();
  assert.match(block, new RegExp(`grid-template-columns: ${SIDEBAR_WIDE}px 1fr`));
  assert.match(block, new RegExp(`grid-template-columns: ${SIDEBAR_ICONS}px 1fr`));
  assert.match(block, new RegExp(`max-width: ${COLUMN_MAX}px`));
  assert.match(block, new RegExp(`max-width: ${FIELD_MAX}px`));
  assert.match(block, new RegExp(`width: ${NUMBER_FIELD}px`));
  assert.match(block, new RegExp(`width: ${PICKER_WIDTH}px`));
  assert.match(block, new RegExp(`\\.st-tabs \\{[^}]*height: ${TAB_BAR_HEIGHT}px`));
  assert.match(block, new RegExp(`\\.st-detail \\{[^}]*padding: ${PADDING}px`));
  assert.match(css, new RegExp(`@media \\(max-width: ${(BREAKPOINT - 0.02).toFixed(2)}px\\) \\{[\\s\\S]*?padding: ${PADDING_COLLAPSED}px`));
  assert.match(css, new RegExp(`\\.hint \\{\\s*font: 400 ${HELP_SIZE}px`));
});

test("the collapsed sidebar is a media query at the breakpoint, and labels and header hide in it", () => {
  assert.match(css, /@media \(max-width: 599\.98px\)/);
  const media = css.slice(css.indexOf("@media (max-width: 599.98px)"));
  assert.match(media, /\.st-head|\.st-navlabel/);
});

test("the layout rules the brief names are in the sheet", () => {
  for (const rule of ["min-width: min-content", "white-space: nowrap", "\\.st-wrapbtn \\{", "\\.st-card input\\[type=\"number\"\\] \\{[^}]*width: 64px", "\\.st-control select \\{[^}]*max-width: 180px"]) {
    assert.match(css, new RegExp(rule), rule);
  }
  assert.doesNotMatch(css, /text-overflow:\s*ellipsis/, "no ellipsis");
  assert.doesNotMatch(css, /-webkit-line-clamp/, "no line clamp");
});

test("word-break: break-all appears once, in the existing code rule, and nowhere in the Settings block", () => {
  assert.equal([...css.matchAll(/word-break:\s*break-all/g)].length, 1);
  assert.match(css, /code \{[^}]*word-break: break-all/);
  assert.doesNotMatch(settingsBlock(), /word-break/);
});

test("the Settings page's dev routes and the cat dev mount are in place", () => {
  assert.match(main, /params\.get\("shot"\)/);
  assert.match(main, /mountShotFrame\(root, Number\(shot\)/);
  assert.match(main, /startSettingsApp\(root, devSettingsBackend\(sample, params\.has\("stress"\), link, failSave, params\.get\("bootproblem"\)\)/);
  assert.match(main, /import\.meta\.env\.DEV \? params\.get\("sample"\) : null/);
  assert.match(catDev, /mountLinkDev\(root, wrap\);\s*\n\s*mountSettingsDev\(root, wrap\);/);
});

test("the render script names the dump, the frame width and the crop it depends on", () => {
  for (const token of ["--dump-dom", "frame-width", "sips -c"]) assert.ok(script.includes(token), token);
  const r = spawnSync("bash", ["-n", fileURLToPath(new URL("../render-settings.sh", import.meta.url))], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
});


test("the accessible names: switchRow's switch is labelled by its label, and rowOf labels each control", () => {
  const sw = fnText(kit, "switchRow");
  assert.ok(sw.includes("aria-labelledby"), "switchRow sets aria-labelledby on the switch");
  assert.match(anyFnText(kit, "rowOf"), /aria-labelledby/, "rowOf sets aria-labelledby on each control");
});

test("pathDisclosure's toggle says whether the paths are shown", () => {
  assert.match(fnText(kit, "pathDisclosure"), /aria-expanded/);
});

test("the render script checks Chrome and each picture, and keeps Vite's log in its profile", () => {
  assert.ok(script.includes('[ -x "$CHROME" ]'), "Chrome is checked before use");
  assert.ok(script.includes('[ -s "$file" ]'), "each picture is checked after it is drawn");
  assert.ok(script.includes('LOG="$PROFILE/'), "Vite's log is inside the profile folder");
});
