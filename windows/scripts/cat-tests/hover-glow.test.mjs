import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DEFAULT_SETTINGS } from "../../src/core/state.ts";
import { THEME } from "../../src/theme.generated.ts";

const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const css = source("style.css");
const glowCss = css.slice(css.indexOf("The hover glow"), css.indexOf("#bot-canvas,\n#greeting-canvas"));

/** Every plain rule in the glow's CSS as { selector, body } (the @property and @keyframes blocks have no mask, so they are harmless here). */
const rules = [...glowCss.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/([^{}]+)\{([^{}]*)\}/g)].map((m) => ({ selector: m[1].trim(), body: m[2] }));

test("the hover glow is on by default and its five colours are the theme's", () => {
  assert.equal(DEFAULT_SETTINGS.hoverGlow, true);
  assert.deepEqual(Object.keys(THEME.glow), ["blue", "purple", "pink", "orange", "magenta"]);
  for (const name of ["blue", "purple", "pink", "orange", "magenta"]) assert.match(glowCss, new RegExp(`var\\(--nm-glow-${name}\\)`), name);
  assert.doesNotMatch(glowCss, /#[0-9a-fA-F]{6}\b/, "no colour is typed in the glow's CSS: they come from shared/theme.json");
});

test("the glow's CSS draws only while hovered: hidden and paused otherwise, and still under reduced motion", () => {
  assert.match(glowCss, /@property --nm-glow-angle/);
  // The edge and the halo's ring are paused until the island is hovered.
  assert.match(glowCss, /#island\.glow::before,\s*#island-halo::before \{[\s\S]*?animation: nm-glow-turn 8s linear infinite paused;/);
  // The edge is hidden until hovered; the halo wrapper is hidden (and not shown at all without the setting) until hovered.
  assert.match(glowCss, /#island\.glow::before \{[^}]*opacity: 0;[^}]*visibility: hidden;/);
  assert.match(glowCss, /#island-halo \{[^}]*display: none;[^}]*opacity: 0;[^}]*visibility: hidden;/);
  assert.match(glowCss, /#island\.glow #island-halo \{\s*display: block;/, "the halo exists only under the setting");
  assert.match(glowCss, /#island\.glow\.hovered #island-halo \{[^}]*opacity: 0\.8;[^}]*visibility: visible;/);
  assert.match(glowCss, /#island\.glow\.hovered #island-halo::before \{\s*animation-play-state: running;/);
  assert.match(glowCss, /#island\.glow\.hovered::before \{[^}]*opacity: 1;[^}]*animation-play-state: running;/);
  assert.match(glowCss, /transition: opacity 0\.2s ease/, "it fades over 0.2 s");
  assert.match(glowCss, /@media \(prefers-reduced-motion: reduce\) \{[\s\S]*?#island-halo::before \{\s*animation: none;/);
  assert.match(glowCss, /inset: 0 -3px -3px;\s*padding: 0 3px 3px;/, "a 3 px ring, open at the top (the screen's edge)");
  assert.match(glowCss, /pointer-events: none;/, "it never takes a click");
  assert.doesNotMatch(glowCss, /::after/, "the old halo pseudo-element is gone: the halo is its own element");
  assert.doesNotMatch(css.replace(glowCss, ""), /nm-glow/, "nothing else uses the glow's names");
});

test("the halo's blur sits on its wrapper, never on the masked ring, so the blur spills past the mask", () => {
  const halo = rules.find((r) => r.selector === "#island-halo");
  assert.ok(halo, "a #island-halo rule exists");
  assert.match(halo.body, /filter: blur\(8px\);/, "the 8 px blur is on the wrapper");
  const masked = rules.filter((r) => /\bmask\b/.test(r.body));
  assert.ok(masked.length > 0, "the ring is masked");
  for (const r of masked) assert.doesNotMatch(r.body, /filter:/, `no blur on the masked ring (${r.selector})`);
  assert.ok(masked.some((r) => r.selector.includes("#island-halo::before")), "the halo's own ring is masked inside the wrapper");
  assert.match(glowCss, /#island-halo \{[^}]*z-index: -2;/, "the halo paints under the sharp edge");
});

test("the island builds the halo as its first child and toggles the glow classes from the switch, the pointer and the mode", () => {
  const isl = source("island/island.ts");
  assert.match(isl, /this\.haloEl = h\("div", \{ id: "island-halo" \}\);/);
  assert.match(isl, /\{ id: "island" \},\s*this\.haloEl,\s*this\.clipEl,/, "the halo is the island's first child, before the clip");
  assert.match(isl, /classList\.toggle\("glow", State\.settings\.hoverGlow\)/);
  assert.match(isl, /classList\.toggle\("hovered", State\.settings\.hoverGlow && this\.wasInIsland && State\.mode !== "hidden"\)/);
  assert.match(isl, /this\.wasInIsland = inIsland;\n    this\.syncGlow\(\);/);
  assert.equal((isl.match(/this\.syncGlow\(\);/g) ?? []).length, 4, "constructor, setMode, applySettings and the pointer");
  const settings = source("settings/general.ts");
  assert.match(settings, /switchRow\("Hover glow"[\s\S]*?hoverGlow: v/);
});
