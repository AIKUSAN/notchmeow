// Shared by the Projects checks: the fixture loader, the source readers and the row check. The fixtures in tests/fixtures/projects/ are generated from
// shared/projects-core.js (docs/PROJECTS-CONTRACT.md).
import fs from "node:fs";

/** One fixture file of tests/fixtures/projects/, parsed. */
export const load = (name) =>
  JSON.parse(fs.readFileSync(new URL(`../../../tests/fixtures/projects/${name}`, import.meta.url), "utf8"));

/** A file of windows/src/, as text. It must exist and not be empty. */
export const source = (rel) => {
  const text = fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
  if (text.trim() === "") throw new Error(`windows/src/${rel} is empty`);
  return text;
};

/**
 * The text with every `//` and `/* *\/` comment replaced by spaces (newlines kept, so the length and every position hold). Strings ('', "") and template
 * literals are kept whole, so a `//` inside "https://x" is not a comment. Regex literals are not understood: none of the pinned files needs them.
 */
export function blankComments(text) {
  let out = "", i = 0;
  const n = text.length;
  const blank = (ch) => (ch === "\n" ? "\n" : " ");
  while (i < n) {
    const c = text[i], d = text[i + 1];
    if (c === "'" || c === '"' || c === "`") {
      out += c; i++;
      while (i < n && text[i] !== c) {
        if (text[i] === "\\" && i + 1 < n) { out += text[i] + text[i + 1]; i += 2; continue; }
        out += text[i]; i++;
      }
      if (i < n) { out += text[i]; i++; }
    } else if (c === "/" && d === "/") {
      while (i < n && text[i] !== "\n") { out += " "; i++; }
    } else if (c === "/" && d === "*") {
      out += "  "; i += 2;
      while (i < n && !(text[i] === "*" && text[i + 1] === "/")) { out += blank(text[i]); i++; }
      if (i < n) { out += "  "; i += 2; }
    } else {
      out += c; i++;
    }
  }
  return out;
}

/** A file of windows/src/ with its comments blanked: a pin written in a comment never matches. */
export const code = (rel) => blankComments(source(rel));

/** The rows of one group of a fixture: an array of objects with exactly `n` rows. Throws otherwise. */
export function rows(fixture, group, n) {
  const g = fixture[group];
  if (!Array.isArray(g)) throw new Error(`fixture group "${group}" is missing or not an array`);
  if (g.length !== n) throw new Error(`fixture group "${group}" has ${g.length} rows, expected ${n}`);
  for (const r of g) if (r === null || typeof r !== "object" || Array.isArray(r)) throw new Error(`fixture group "${group}" has a row that is not an object`);
  return g;
}
