// The one slicer the Settings pins share (Task 6, part 2): a function's or a CSS rule's text, cut at a known end, read from the source as text. It is not a test file
// (no `.test.mjs`), so `check:settings` does not run it; kit.test, drift.test, presence.test and contrast.test import it. Each cut fails the test when its start or its end is missing.
import assert from "node:assert/strict";

/** The text from `signature` (a string, or a RegExp at its first match) to the first `end` after it, `end` included. */
export function sliceBetween(text, signature, end) {
  const from = typeof signature === "string" ? text.indexOf(signature) : text.search(signature);
  assert.ok(from >= 0, `${signature} is in the text`);
  const close = text.indexOf(end, from);
  assert.ok(close > from, `${signature} closes at ${JSON.stringify(end)}`);
  return text.slice(from, close + end.length);
}

/** One top-level exported function: from `export function NAME(` to the closing brace at column 0. */
export function fnText(text, name) {
  return sliceBetween(text, `export function ${name}(`, "\n}\n");
}

/** A top-level function with or without `export`: from `function NAME(` to the closing brace at column 0. */
export function anyFnText(text, name) {
  return sliceBetween(text, new RegExp(`(?:export )?function ${name}\\(`), "\n}\n");
}

/** The declarations of the CSS rule whose selector is exactly `selector` (one selector, at the start of a line): its body without the braces. */
export function ruleBody(css, selector) {
  const esc = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const m = new RegExp(`^[ \\t]*${esc}[ \\t]*\\{([^}]*)\\}`, "m").exec(css);
  assert.ok(m, `the CSS rule ${selector} exists`);
  return m[1];
}
