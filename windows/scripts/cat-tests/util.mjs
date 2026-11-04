// Shared by the cat checks: the fixture loader and the 1e-9 comparison.
// The fixtures in tests/fixtures/cat/ are generated from design/prototype/cat-core.js (see docs/CAT-CONTRACT.md).
import assert from "node:assert/strict";
import fs from "node:fs";

export const TOLERANCE = 1e-9;

/** One fixture file of tests/fixtures/cat/, parsed. */
export const load = (name) =>
  JSON.parse(fs.readFileSync(new URL(`../../../tests/fixtures/cat/${name}`, import.meta.url), "utf8"));

const isObj = (x) => x !== null && typeof x === "object" && !Array.isArray(x);

/** Deep compare with a numeric tolerance. Returns the list of differences, empty when equal. */
export function compare(got, want, at = "$", out = []) {
  if (typeof got === "number" && typeof want === "number") {
    if (!(Math.abs(got - want) <= TOLERANCE)) out.push(`${at}: ${got} vs ${want}`);
  } else if (Array.isArray(got) && Array.isArray(want)) {
    if (got.length !== want.length) out.push(`${at}: length ${got.length} vs ${want.length}`);
    for (let i = 0; i < Math.min(got.length, want.length); i++) compare(got[i], want[i], `${at}[${i}]`, out);
  } else if (isObj(got) && isObj(want)) {
    const gk = Object.keys(got).sort(), wk = Object.keys(want).sort();
    if (gk.join() !== wk.join()) out.push(`${at}: keys ${gk.join()} vs ${wk.join()}`);
    for (const k of gk) if (k in want) compare(got[k], want[k], `${at}.${k}`, out);
  } else if (got !== want) out.push(`${at}: ${JSON.stringify(got)} vs ${JSON.stringify(want)}`);
  return out;
}

/** Fails with the first differences listed. `got` goes through JSON first, as the fixtures did (a function or undefined drops out). */
export function same(got, want, what = "value") {
  const diffs = compare(JSON.parse(JSON.stringify(got)), want);
  assert.deepEqual(diffs.slice(0, 8), [], `${what}: ${diffs.length} difference(s) from the fixture`);
}

export const near = (a, b, eps = TOLERANCE) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);

/** Every number in a value is finite. */
export function finite(v, at = "$") {
  if (typeof v === "number") assert.ok(Number.isFinite(v), `${at} is ${v}`);
  else if (typeof v === "function") return;
  else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) finite(x, `${at}.${k}`);
}

/**
 * The highest point (smallest y) an ear reaches in the world, found by walking the whole outline the renderer draws (drawEar's
 * three quadratic curves) and not by the formula under test: ear space, then head space (turned by the ear's tilt, moved to
 * its base), then the world (the head's tilt and squash, then its position). `L` is a layout(), `s` the pose, `e` one of `L.ears`.
 */
export function earTop(L, s, e) {
  const R = L.R, { h, bw, tip, cx } = e;
  const segs = [
    [[-bw, 0.25 * R], [-bw * cx, -h * 0.4], [-tip * 0.9, -h + tip * 1.3]],
    [[-tip * 0.9, -h + tip * 1.3], [0, -h - tip * 0.35], [tip * 0.9, -h + tip * 1.3]],
    [[tip * 0.9, -h + tip * 1.3], [bw * cx, -h * 0.4], [bw, 0.25 * R]],
  ];
  let best = Infinity;
  for (const [a, b, c] of segs) for (let i = 0; i <= 400; i++) {
    const t = i / 400, m = 1 - t;
    const x = m * m * a[0] + 2 * m * t * b[0] + t * t * c[0], y = m * m * a[1] + 2 * m * t * b[1] + t * t * c[1];
    const hx = e.bx + x * Math.cos(e.rot) - y * Math.sin(e.rot), hy = e.by + x * Math.sin(e.rot) + y * Math.cos(e.rot);
    best = Math.min(best, L.head.y + Math.sin(s.tilt) * s.sx * hx + Math.cos(s.tilt) * s.sy * hy);
  }
  return best;
}
