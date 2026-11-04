import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The Settings window's glue is checked by source pins (it needs a browser): the Cat section keeps every row it had, in its order, and the Display rows are added around them.
const read = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const cat = read("settings/cat.ts"), display = read("settings/display.ts"), css = read("settings/settings.css");

test("the Cat tabs: the cards come in the tab order, and the rows keep their order within each tab", () => {
  const at = (s) => { const i = cat.indexOf(s); assert.ok(i > 0, s); return i; };
  const cards = ['card("Main cat"', 'card("Look"', 'card("Desktop"', 'card("Personality"', 'card("Motion"', 'card("Every cat"', 'card("Display"'];
  const places = cards.map(at);
  assert.deepEqual([...places].sort((a, b) => a - b), places, "the cards in tab order");
  const tabs = [
    ['row("Collar"', 'row("This cat\'s collar"', 'row("Fur lines"'],
    ['row("Personality"', "...sliders.map((sl) => sl.el)"],
    ['row("Motion style"', 'row("This cat\'s motion"'],
  ];
  for (const rows of tabs) {
    const p = rows.map(at);
    assert.deepEqual([...p].sort((a, b) => a - b), p, rows.join(", "));
  }
  assert.ok(at('card("Your two cats"') > 0 && at('card("Cats for your agents"') > 0, "the pair and agents cards");
});

test("Character is Main cat: the grid is named so, with a line that says what it is, and the word Character is gone from the section", () => {
  assert.match(cat, /"aria-label": "Main cat"/);
  assert.match(cat, /Main cat: the cat of One cat mode, of the integration pills/);
  assert.doesNotMatch(cat, /"Character"/);
});

test("every edit of the section goes through withCatSettings, so a Cat settings row never drops the display keys", () => {
  assert.match(cat, /host\.put\(withCatSettings\(host\.cat\(\), next\), final\);/);
  assert.match(cat, /cat\(\): CatBlock;/);
  assert.match(cat, /put\(next: CatBlock, final: boolean\): void;/);
  assert.match(read("settings/app.ts"), /cat: cleanCatBlock\(s\.cat\)/);
});

test("the Display rows: the picker, the pair's pickers, Cats for your agents with its dice and Reset to defaults, built from the window's own rows", () => {
  for (const s of ['ui.row("Display"', "`Pair, cat ${i + 1}`", "Cats for your agents", '"Reset to defaults"', '"\\u{1F3B2}"', "Roll a new random cat", "withDisplayMode", "withPair", "withAgentCat(", "rerollAgentCat", "assignAgentCats"]) assert.ok(display.includes(s), s);
  assert.match(display, /\["one", "One cat"\], \["perAgent", "A cat for each agent"\], \["two", "Two cats"\]/);
});

test("the previews draw only while Settings can be seen: display.draw is called by the section's one VisibleLoop, and display.ts runs no loop of its own", () => {
  assert.match(cat, /if \(preview\) drawOne\(preview, previewCv, PREVIEW_W, PREVIEW_H, dt\);\s*display\?\.draw\(dt\);/);
  assert.doesNotMatch(display, /requestAnimationFrame|setInterval|setTimeout|VisibleLoop/);
});

test("the new CSS rules are new class names only: the Display block adds .cat-notch, .cat-agents-box, .cat-agents, .cat-agent and .dice, and no existing selector", () => {
  const start = css.indexOf("/* Display (sub-project B)"), end = css.indexOf("/* The two ends of a trait slider");
  assert.ok(start > 0 && end > start);
  const block = css.slice(start, end).replace(/\/\*[\s\S]*?\*\//g, "");
  const selectors = [...block.matchAll(/([^{}]+)\{/g)].map((m) => m[1].trim());
  assert.ok(selectors.length >= 8, `${selectors.length} selectors`);
  for (const sel of selectors) assert.match(sel, /^\.(cat-notch|cat-agents-box|cat-agents|cat-agent|cat-agent-cv|dice)\b/, sel);
});

test("the six personality sliders stay on one line, in line with each other, from the window's 560 px down to its 460 px minimum: a grid on those rows only", () => {
  assert.match(cat, /el\.classList\.add\("cat-trait"\)/, "the six slider rows, and no other row, get the class");
  assert.equal(cat.split('"cat-trait"').length - 1, 1);
  const body = (selector) => {
    const at = css.indexOf(`${selector} {`);
    assert.ok(at > 0, selector);
    return css.slice(at, css.indexOf("}", at));
  };
  assert.match(body(".row.cat-trait"), /display: grid;/);
  // Narrow windows (under 600 px wide, where the sliders would not fit in one line): the name goes above, the two ends below.
  const narrow = css.slice(css.indexOf("@media (max-width: 599.98px) {", css.indexOf(".row.cat-trait {")));
  assert.match(narrow, /\.row\.cat-trait \{\s*grid-template-columns: 1fr 1fr;\s*grid-template-areas: "label label" "slider slider" "low high";/);
  assert.match(body(".row.cat-trait"), /grid-template-columns: minmax\(72px, 132px\) minmax\(76px, 84px\) minmax\(56px, 140px\) minmax\(76px, 84px\);/);
  assert.match(body(".cat-trait input[type=\"range\"]"), /width: 100%;/);
  assert.match(body(".row.cat-trait > label,\n.cat-trait .cat-low,\n.cat-trait .cat-high"), /min-width: 0;[\s\S]*white-space: nowrap;/);
  // Every other row keeps the rule it had: the wrapping row is still the window's own.
  assert.match(body(".row"), /display: flex;[\s\S]*flex-wrap: wrap;/);
  assert.match(body(".row > label"), /min-width: 132px;/);
});
