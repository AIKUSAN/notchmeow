// Pins for the Settings palette (Task 6 of the Windows and Linux Settings restyle): the dark tokens are today's literals (--dim-2 raised), the light
// tokens mirror the Mac's light look, every text pair of both palettes is at least 4.5:1 (WCAG, translucent colours blended over --card), the two
// light blocks are equal, no colour literal is left outside the tokens, and the page follows the system's appearance. They read the source as text.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { ruleBody } from "./slice.mjs";

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const css = read("src/settings/settings.css");
const html = read("settings.html");
const devices = read("src/settings/devices.ts");

/** The declarations of a rule body as a Map: property (or --token) to its value. */
function decls(body) {
  const plain = body.replace(/\/\*[\s\S]*?\*\//g, "");
  return new Map([...plain.matchAll(/([a-z0-9-]+)\s*:\s*([^;]+);/g)].map((m) => [m[1], m[2].trim().replace(/\s+/g, " ")]));
}

const DARK = decls(ruleBody(css, ":root"));
const LIGHT_MEDIA = decls(ruleBody(css, ':root:not([data-theme="dark"])'));
const LIGHT = decls(ruleBody(css, ':root[data-theme="light"]'));

/** A colour value as RGBA numbers: #rgb, #rrggbb, rgb() or rgba(). */
function parse(value) {
  const v = value.trim();
  let m = /^#([0-9a-f]{3})$/i.exec(v);
  if (m) return { r: parseInt(m[1][0] + m[1][0], 16), g: parseInt(m[1][1] + m[1][1], 16), b: parseInt(m[1][2] + m[1][2], 16), a: 1 };
  m = /^#([0-9a-f]{6})$/i.exec(v);
  if (m) return { r: parseInt(m[1].slice(0, 2), 16), g: parseInt(m[1].slice(2, 4), 16), b: parseInt(m[1].slice(4, 6), 16), a: 1 };
  m = /^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$/.exec(v);
  if (m) return { r: Number(m[1]), g: Number(m[2]), b: Number(m[3]), a: m[4] === undefined ? 1 : Number(m[4]) };
  throw new Error(`not a colour: ${value}`);
}

/** `fg` (possibly translucent) painted over the opaque `bg`. */
function over(fg, bg) {
  return { r: fg.a * fg.r + (1 - fg.a) * bg.r, g: fg.a * fg.g + (1 - fg.a) * bg.g, b: fg.a * fg.b + (1 - fg.a) * bg.b, a: 1 };
}

/** The token's colour as an opaque surface: a translucent one is blended over --card, as the Mac's SettingsColors does. */
function surface(palette, name) {
  const card = parse(palette.get("--card"));
  const c = parse(palette.get(`--${name}`));
  return c.a < 1 ? over(c, card) : c;
}

/** WCAG relative luminance and contrast ratio: the formula of the Mac's SettingsColors.contrast. */
function luminance({ r, g, b }) {
  const lin = (c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}
function ratio(a, b) {
  const la = luminance(a), lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/** Every text pair the brief names, as [text token, surface token]. */
const TEXT_PAIRS = [
  ...["ink", "dim", "dim-2"].flatMap((fg) => ["bg", "card", "diff-bg", "option-bg"].map((bg) => [fg, bg])),
  ["dim", "field"],
  ["dim-2", "field"],
  ["green", "card"],
  ["red", "card"],
  ["amber", "card"],
  ["add-ink", "diff-bg"],
  ["del-ink", "diff-bg"],
  ["ok-ink", "ok-bg"],
  ["err-ink", "err-bg"],
  ["warn-ink", "warn-bg"],
  ["danger-ink", "danger-bg"],
  ["primary-ink", "ink"],
  ["ink", "btn"],
  ["dim", "btn"],
  ["dim-2", "btn"],
  ["dim", "soft"],
  ["dim-2", "soft"],
  ["ink", "field"],
];

for (const [label, palette] of [["dark", DARK], ["light", LIGHT]]) {
  test(`the ${label} palette: every text pair is at least 4.5:1`, () => {
    for (const [fg, bg] of TEXT_PAIRS) {
      const backdrop = surface(palette, bg);
      const t = parse(palette.get(`--${fg}`));
      const r = ratio(t.a < 1 ? over(t, backdrop) : t, backdrop);
      assert.ok(r >= 4.5, `${label}: --${fg} over --${bg} is ${r.toFixed(2)}:1`);
    }
  });
}

test("the dark palette is the first :root block: color-scheme dark light, and today's literals except --dim-2 (#8d929b, 4.90:1 over the field)", () => {
  assert.equal(DARK.get("color-scheme"), "dark light");
  const today = {
    "--ink": "#f5f6f8", "--dim": "#9398a1", "--dim-2": "#8d929b", "--bg": "#0b0c0e", "--card": "#141518",
    "--hairline": "rgba(255, 255, 255, 0.07)", "--green": "#22c55e", "--red": "#f4505e", "--amber": "#f5a524",
    "--btn": "rgba(255, 255, 255, 0.09)", "--btn-hover": "rgba(255, 255, 255, 0.15)", "--primary-ink": "#0b0c0e", "--primary-hover": "#fff",
    "--danger-bg": "rgba(244, 80, 94, 0.16)", "--danger-ink": "#ff8d97", "--switch-off": "rgba(255, 255, 255, 0.15)", "--knob": "#fff",
    "--track": "rgba(255, 255, 255, 0.2)", "--field": "rgba(255, 255, 255, 0.07)", "--field-line": "rgba(255, 255, 255, 0.28)",
    "--option-bg": "#1a1c20", "--diff-bg": "#08090b", "--add-ink": "#86efac", "--del-ink": "#ff8d97", "--ok-bg": "rgba(34, 197, 94, 0.12)",
    "--ok-ink": "#86efac", "--err-bg": "rgba(244, 80, 94, 0.14)", "--err-ink": "#ff8d97", "--warn-bg": "rgba(245, 165, 36, 0.13)",
    "--warn-ink": "#fbc06a", "--cell-hover": "rgba(255, 255, 255, 0.09)", "--cell-on": "rgba(255, 255, 255, 0.1)",
    "--cell-on-line": "rgba(255, 255, 255, 0.55)", "--soft": "rgba(255, 255, 255, 0.05)",
  };
  for (const [name, value] of Object.entries(today)) assert.equal(DARK.get(name), value, name);
  assert.ok(ratio(parse(DARK.get("--dim-2")), surface(DARK, "field")) >= 4.5);
});

test("the light palette: the media query, guarded by :root:not([data-theme=\"dark\"]), holds color-scheme light and the tokens", () => {
  assert.equal(LIGHT_MEDIA.get("color-scheme"), "light");
  assert.equal(LIGHT.get("color-scheme"), "light");
  assert.equal(LIGHT.get("--bg"), "#ececec");
  assert.equal(LIGHT.get("--card"), "#ffffff");
  assert.ok(css.indexOf('@media (prefers-color-scheme: light)') > 0);
});

test("the two light blocks are identical, and the dark-forced block only sets color-scheme dark", () => {
  assert.deepEqual([...LIGHT_MEDIA].sort(), [...LIGHT].sort());
  const forcedDark = decls(ruleBody(css, ':root[data-theme="dark"]'));
  assert.deepEqual([...forcedDark], [["color-scheme", "dark"]]);
});

test("every token block comes before the Wardrobe comment", () => {
  const wardrobe = css.indexOf("/* Wardrobe (sub-project I)");
  assert.ok(wardrobe > 0);
  for (const m of css.matchAll(/:root[^{]*\{/g)) assert.ok(m.index < wardrobe, `${m[0]} before the Wardrobe comment`);
});

/** The stylesheet with its comments and its token blocks (the :root rules and the light media query) removed. The token blocks hold no nested braces, so one regex each. */
function outsideTokens(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/@media \(prefers-color-scheme: light\) \{[\s\S]*?\}\s*\}/g, "")
    .replace(/:root[^{]*\{[^}]*\}/g, "");
}

test("no colour literal is left outside the tokens, except #000 in the three cat-preview rules", () => {
  const rest = outsideTokens(css);
  assert.doesNotMatch(rest, /rgba?\(/, "no rgb() outside the tokens");
  const hex = [...rest.matchAll(/#[0-9a-fA-F]{3,8}\b/g)].map((m) => m[0]);
  assert.deepEqual(hex, ["#000", "#000", "#000"], "only the three #000 backgrounds");
  const rules = [...rest.matchAll(/(\.cat-preview|\.cat-notch|\.cat-agent-cv) \{[^}]*background: #000;/g)].map((m) => m[1]);
  assert.deepEqual(rules.sort(), [".cat-agent-cv", ".cat-notch", ".cat-preview"]);
});

/** The colour token a rule's property names: `var(--x)` gives "x"; a literal gives null. */
const tokenOf = (value) => /var\(--([\w-]+)\)/.exec(value ?? "")?.[1] ?? null;

test("the selected sidebar row's text is 4.5:1 over its fill, and the tone dots are 3:1 over --card (non-text), in both palettes", () => {
  const navOn = decls(ruleBody(css, '.st-nav[aria-current="page"]'));
  const fill = tokenOf(navOn.get("background"));
  const ink = tokenOf(navOn.get("color"));
  assert.ok(fill && ink, "the selected row takes its fill and its text from tokens");
  const dots = {
    "st-chip::before": tokenOf(decls(ruleBody(css, ".st-chip::before")).get("background")),
    "st-ok": tokenOf(decls(ruleBody(css, ".st-chip.st-ok::before")).get("background")),
    "st-warn": tokenOf(decls(ruleBody(css, ".st-chip.st-warn::before")).get("background")),
    "st-error": tokenOf(decls(ruleBody(css, ".st-chip.st-error::before")).get("background")),
  };
  for (const [label, palette] of [["dark", DARK], ["light", LIGHT]]) {
    const r = ratio(parse(palette.get(`--${ink}`)), surface(palette, fill));
    assert.ok(r >= 4.5, `${label}: the selected row's --${ink} over --${fill} is ${r.toFixed(2)}:1`);
    for (const [dot, token] of Object.entries(dots)) {
      assert.ok(token, `${dot} takes its colour from a token`);
      const d = ratio(surface(palette, token), surface(palette, "card"));
      assert.ok(d >= 3, `${label}: the ${dot} dot (--${token}) over --card is ${d.toFixed(2)}:1, below the 3:1 a non-text mark needs`);
    }
  }
});

test("the bad check word (.check.bad) is 4.5:1 over --card in both palettes", () => {
  const token = tokenOf(decls(ruleBody(css, ".check.bad")).get("color"));
  assert.ok(token, ".check.bad takes its colour from a token");
  for (const [label, palette] of [["dark", DARK], ["light", LIGHT]]) {
    const r = ratio(surface(palette, token), surface(palette, "card"));
    assert.ok(r >= 4.5, `${label}: .check.bad (--${token}) over --card is ${r.toFixed(2)}:1`);
  }
});

test(".hint is 12px, coloured by var(--dim)", () => {
  const hint = ruleBody(css, ".hint");
  assert.match(hint, /font: 400 12px var\(--font\);/);
  assert.match(hint, /color: var\(--dim\);/);
});

test("settings.html has no inline background and asks for both colour schemes from the first paint", () => {
  assert.doesNotMatch(html, /style="[^"]*background\s*:/, "no inline background");
  assert.match(html, /<meta name="color-scheme" content="dark light"/);
  assert.match(html, /<body class="settings-window"/);
});

test("the paired-offline dot takes the token; the other two dots keep their colours", () => {
  assert.match(devices, /pairedOffline: "var\(--dim-2\)"/);
  assert.match(devices, /pairedOnline: "#22c55e"/);
  assert.match(devices, /available: "#60a5fa"/);
});
