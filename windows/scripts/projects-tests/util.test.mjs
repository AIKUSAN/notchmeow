import test from "node:test";
import assert from "node:assert/strict";
import { blankComments, code, rows } from "./util.mjs";

test("code() blanks a pin written in a line comment and in a block comment", () => {
  const out = blankComments("const a = 1; // export const pin = 2;\n/* export const pin2 = 3; */ const b = 4;");
  assert.ok(!out.includes("pin"), "no pin left in a comment");
  assert.ok(out.includes("const a = 1;") && out.includes("const b = 4;"), "the code stays");
  assert.equal(out.length, "const a = 1; // export const pin = 2;\n/* export const pin2 = 3; */ const b = 4;".length, "same length, so positions hold");
});

test("code() keeps a // inside a string and inside a template literal whole", () => {
  const src = 'const u = "https://x"; const t = `a // b`; // gone';
  const out = blankComments(src);
  assert.ok(out.includes('"https://x"'), "the string is kept");
  assert.ok(out.includes("`a // b`"), "the template literal is kept");
  assert.ok(!out.includes("gone"), "the comment after them is blanked");
});

test("code() reads a real source file without its comments", () => {
  const out = code("projects/core.ts");
  assert.ok(!out.includes("Pure: no clock"), "comment blanked");
  assert.ok(out.includes("export type StateWord"), "code kept");
});

test("rows() throws on a missing group, a group of the wrong length and a row that is not an object", () => {
  assert.throws(() => rows({}, "cases", 1));
  assert.throws(() => rows({ cases: [{}] }, "cases", 2));
  assert.throws(() => rows({ cases: [1] }, "cases", 1));
  assert.throws(() => rows({ cases: [null] }, "cases", 1));
  assert.deepEqual(rows({ cases: [{ a: 1 }] }, "cases", 1), [{ a: 1 }]);
});
