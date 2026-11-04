import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the link (G2) is wired into the page, pinned as source text: no test program can run the island's DOM, so these say what must stay true. What the cards look like is looked at in the `?dev`
// page's Link panel and in settings.html?linkdev=on (the checkpoint's pictures).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const walk = (dir) => fs.readdirSync(new URL(`../../src/${dir}`, import.meta.url), { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(`${dir}${e.name}/`) : [`${dir}${e.name}`]));
const all = walk("").filter((f) => f.endsWith(".ts"));
/** The code of a source file without its comments, for the checks that read what the code does and not what it says. */
const code = (rel) => source(rel).replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");

test("the link view is new: registered after the shelf, laid out like the approval card, and no other view is touched", () => {
  const views = source("views/views.ts");
  assert.match(views, /import \{ buildLink \} from "\.\/link";/);
  assert.match(views, /map\.set\("shelf", buildShelf\(actions\.shelf\)\);\s*map\.set\("link", buildLink\(\)\);/);
  const layout = source("core/layout.ts");
  assert.match(layout, /\| "shelf"\s*\| "link";/);
  assert.match(layout, /link: \{ height: 160, botX: 62, botY: null, botDiameter: 56, agentMode: "column" \},/);
  assert.doesNotMatch(source("views/upload.ts"), /link/i, "the upload views are not touched");
});

test("the card never accepts for the user: the only call that says yes to an offer is the Accept button", () => {
  const callers = all.filter((f) => /\brespondOffer\(\s*true/.test(source(f)));
  assert.deepEqual(callers, ["views/link.ts"]);
  const view = source("views/link.ts");
  assert.match(view, /btn\("Accept", "primary", \(\) => backend\(\)\?\.respondOffer\(true, shownOf\(c\)\)\)/);
  assert.match(view, /btn\("Decline", "secondary", \(\) => backend\(\)\?\.respondOffer\(false, shownOf\(c\)\)\)/);
  assert.doesNotMatch(view, /setInterval|setTimeout|requestAnimationFrame|Bridge|invoke\(/, "the view draws; it has no timer and calls nothing out but through the backend");
});

test("every button of a card hands back the card it was drawn on", () => {
  const view = source("views/link.ts");
  for (const call of ["answerPair(false", "answerPair(true", "respondOffer(false", "respondOffer(true", "cancelReceiving(", "dismiss("]) {
    const at = view.indexOf(call);
    assert.ok(at > 0, call);
    assert.match(view.slice(at, at + 90), /shownOf\(c\)/, call);
  }
});

test("the shelf's device bar is a new file the shelf view includes; the shelf view itself gains three added lines and one rewritten, and calls nothing out", () => {
  const shelf = source("views/shelf.ts");
  assert.match(shelf, /import \{ buildDeviceBar \} from "\.\/shelfdevice";/);
  assert.match(shelf, /const device = buildDeviceBar\(\);/);
  assert.match(shelf, /h\("div", \{ class: "sh-head" \}, title, count, device\.el, h\("span", \{ class: "sh-spacer" \}\), sendMany, clearAll\)/);
  assert.match(shelf, /sync\(\) \{\s*device\.sync\(\);/);
  assert.doesNotMatch(shelf, /\.link|Bridge/, "the shelf view's own pin: no call out; the device bar is the other file");
  const bar = source("views/shelfdevice.ts");
  assert.match(bar, /State\.link\.backend\?\.send\(\[\.\.\.State\.shelf\.selected\], r\.id\)/, "ids of the shelf and the machine's id; never a path");
  assert.doesNotMatch(bar, /setInterval|setTimeout|requestAnimationFrame|\.path\b/);
  assert.match(source("shelf/icons.ts"), /device: "M5 6h14v9H5zM2 19h20",/);
});

test("the page hands Rust ids, never a path, a key or an address", () => {
  assert.match(source("link/backend.ts"), /send: \(ids, to\) => post\("link_send", \{ ids, to \}\),/);
  assert.doesNotMatch(code("link/backend.ts"), /path|address|hostname|secret/i);
  assert.doesNotMatch(code("link/model.ts"), /\bpath\b|address/i);
});

test("main.ts attaches the backend, tells the island about a card, and says when the shelf is on screen; the mock and the dev seeds load only on the dev server", () => {
  const main = source("main.ts");
  assert.match(main, /import \{ bridgeLinkBackend \} from "\.\/link\/backend";/);
  assert.match(main, /import \{ ShelfLook, linkChanged \} from "\.\/island\/link";/);
  assert.match(main, /import "\.\/link\/link\.css";/);
  assert.match(main, /const linkBackend = IS_TAURI \? bridgeLinkBackend\(\) : import\.meta\.env\.DEV \? \(await import\("\.\/link\/mock"\)\)\.mockLinkBackend\(\) : null;/);
  assert.match(main, /State\.link\.attach\(linkBackend, \(prev, next\) => linkChanged\(island, prev, next\)\);/);
  assert.match(main, /State\.subscribe\(\(\) => shelfLook\.sync\(State\.view, State\.mode, \(open\) => State\.link\.backend\?\.setShelfOpen\(open\)\)\);/);
  const settings = source("settings/main.ts"), app = source("settings/app.ts");
  assert.match(settings, /const linkdev = import\.meta\.env\.DEV \? new URLSearchParams\(location\.search\)\.get\("linkdev"\) : null;/);
  assert.match(settings, /\(await import\("\.\.\/link\/devseed"\)\)\.devBackend\(linkdev\)/);
  assert.match(app, /devicesSection\(\{ backend: ctx\.backend\.link/);
  assert.match(source("cat/dev.ts"), /mountLinkDev\(root, wrap\);/);
  const importers = all.filter((f) => /from "\.{1,2}\/(link\/)?(mock|devseed|devlink)(\.ts)?"/.test(source(f)));
  assert.deepEqual(importers.sort(), ["cat/dev.ts", "link/devlink.ts", "link/devseed.ts"].sort(), "static imports of the stand-in are the dev panel's alone; main.ts and settings use a dynamic import behind DEV");
});

test("the style sheet only gains lk- rules and one modifier of the shelf head; no rule of a shipped view changes", () => {
  const css = source("link/link.css").replace(/\/\*[\s\S]*?\*\//g, "");
  const selectors = [...css.matchAll(/([^{}]+)\{/g)].flatMap((m) => m[1].split(",").map((s) => s.trim()));
  assert.ok(selectors.length > 20);
  for (const s of selectors) assert.match(s, /^(\.lk-[\w-]+(\.off)?|\.lk-body \.btn:disabled|\.lk-pairrow \.sub|\.sh-head\.sh-choosing > :not\(\.sh-title\):not\(\.lk-devbar\)|\.sh-head > \.sh-count|\.sh-head > \.btn)$/, s);
});

test("the shelf head keeps its count and its buttons on one line and lets the status line give way; the card's title keeps its descenders", () => {
  const css = source("link/link.css").replace(/\/\*[\s\S]*?\*\//g, "");
  assert.match(css, /\.sh-head > \.sh-count, \.sh-head > \.btn \{\s*flex-shrink: 0;\s*white-space: nowrap;\s*\}/);
  assert.match(css, /\.lk-title \{\s*white-space: nowrap;\s*overflow: hidden;\s*text-overflow: ellipsis;\s*padding-bottom: /);
});

test("the chips offer the paired machines: online first, an offline one greyed and disabled, and a click on it sends nothing", () => {
  const bar = source("views/shelfdevice.ts");
  assert.match(bar, /const targets = \[\.\.\.sendTargets\(snap\.rows\), \.\.\.snap\.rows\.filter\(\(r\) => r\.state === "pairedOffline"\)\];/, "online first, then the offline ones");
  assert.match(bar, /disabled: !online,/);
  assert.match(bar, /title: online \? `Send to \$\{r\.name\}` : `\$\{r\.name\} is not on the network`,/);
  assert.match(bar, /onclick: \(\) => \{\s*if \(!online\) return;/, "a click on an offline chip sends nothing, even if the browser let one through");
});

test("the firewall help shows only while Visible on this network is on", () => {
  assert.match(source("settings/devices.ts"), /help\.style\.display = snap\.visible \? "" : "none";/);
});

test("Settings → Devices says when it is on screen as a state, from the section's visibility, and has no timer", () => {
  const dev = source("settings/devices.ts");
  assert.match(dev, /new IntersectionObserver\(/);
  assert.match(dev, /backend\.setDevicesOpen\(open\)/);
  assert.match(dev, /window\.addEventListener\("pagehide", onHide\)/);
  assert.doesNotMatch(dev, /setInterval|setTimeout|requestAnimationFrame/);
  assert.match(dev, /btn|h\("button", \{ class: "switch"/);
});

test("Settings → Devices: the first state reply never overwrites a newer push, and a rejected call or listen is not an unhandled rejection", () => {
  const dev = source("settings/devices.ts");
  assert.match(dev, /let pushed = false;\s*const off = backend\.onSnapshot\(\(s\) => \{\s*pushed = true;\s*sync\(s\);\s*\}\);\s*void backend\.state\(\)\.then\(\(s\) => \{ if \(!pushed\) sync\(s\); \}\)\.catch\(\(\) => \{\}\);/);
  assert.match(dev, /let ok: boolean;\s*try \{ ok = await backend\.setName\(name\.value\); \} catch \{ return; \}/);
  assert.match(source("link/backend.ts"), /void listen<unknown>\("link", \(e\) => cb\(cleanSnapshot\(e\.payload\)\)\)\s*\.then\([\s\S]*?\)\s*\.catch\(/);
});

test("the island's part: a card opens it, a card with buttons holds it, the shelf's sight is a state; no timer in island/link.ts", () => {
  const isl = source("island/link.ts");
  assert.match(isl, /if \(t\.alert\) host\.alert\("link"\);\s*if \(t\.hold\) host\.holdOpen\(\);\s*if \(t\.release && !pinnedByRequest\) host\.dropPin\(\);\s*if \(t\.collapse\) host\.collapse\(\);/);
  assert.doesNotMatch(isl, /setInterval|setTimeout|requestAnimationFrame/);
});
