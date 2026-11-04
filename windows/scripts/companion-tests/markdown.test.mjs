import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { parseMarkdown, renderBlocks } from "../../src/companion/markdown.ts";
import { code } from "../projects-tests/util.mjs";

// A model's reply is data. parseMarkdown is read here (Node has no DOM); renderBlocks builds nodes with createElement and textContent only, so the source
// pins below are the guard for it.

const text = (s) => ({ t: "text", s });

test("bold, italic and code in a paragraph come apart from the text around them", () => {
  assert.deepEqual(parseMarkdown("a **bold** and *it* and `code`"), [
    { t: "p", inl: [text("a "), { t: "b", s: "bold" }, text(" and "), { t: "i", s: "it" }, text(" and "), { t: "code", s: "code" }] },
  ]);
});

test("dashes make a bullet list and numbers make a numbered one, and a change of kind starts a new list", () => {
  assert.deepEqual(parseMarkdown("- one\n* two\n\n1. first\n2. second"), [
    { t: "ul", items: [[text("one")], [text("two")]] },
    { t: "ol", items: [[text("first")], [text("second")]] },
  ]);
});

test("a fenced block keeps its text exactly, and its language word is not a class or a field", () => {
  assert.deepEqual(parseMarkdown("```js\nconst a = '<b>';\n\n  x\n```"), [{ t: "pre", s: "const a = '<b>';\n\n  x" }]);
  assert.deepEqual(parseMarkdown("```\n```"), [{ t: "pre", s: "" }]);
});

test("markup is shown as text", () => {
  assert.deepEqual(parseMarkdown("<img src=x onerror=alert(1)>"), [{ t: "p", inl: [text("<img src=x onerror=alert(1)>")] }]);
});

test("only http and https links become links; any other link is its whole text", () => {
  assert.deepEqual(parseMarkdown("[a](https://x.y/z)"), [{ t: "p", inl: [{ t: "link", s: "a", href: "https://x.y/z" }] }]);
  assert.deepEqual(parseMarkdown("[a](http://x.y)"), [{ t: "p", inl: [{ t: "link", s: "a", href: "http://x.y" }] }]);
  for (const bad of ["[click](javascript:alert(1))", "[x](file:///C:/)"]) {
    assert.deepEqual(parseMarkdown(bad), [{ t: "p", inl: [text(bad)] }], bad);
  }
});

test("a link URL is a clean http or https address: no whitespace, quote, markup, control character or backslash, and at most 2,048 characters", () => {
  const rejected = [
    "https://x y",
    "https://x\n\"z",
    "https://x\"y",
    "https://x<y",
    "https://x>y",
    "https://x\\y",
    "https://x\ty",
    "https://x y",
    "https://x y",
    "https://x\u0000y",
    "https://x\u007fy",
    "https://x`y",
    "https://x^y",
    "https://x|y",
    "https://x{y}",
    "https://" + "a".repeat(3000),
  ];
  for (const url of rejected) {
    const src = `[a](${url})`;
    assert.deepEqual(parseMarkdown(src), [{ t: "p", inl: [text(src)] }], JSON.stringify(url).slice(0, 60));
  }
  for (const url of ["https://x.y/z?q=1&r=2#frag", "https://x.y/a%20b/café/中", "http://x.y/" + "a".repeat(2048 - 11)]) {
    assert.deepEqual(parseMarkdown(`[a](${url})`), [{ t: "p", inl: [{ t: "link", s: "a", href: url }] }], url.slice(0, 40));
  }
});

test("a heading is a bold paragraph, and blank lines split paragraphs", () => {
  assert.deepEqual(parseMarkdown("# Title"), [{ t: "p", inl: [{ t: "b", s: "Title" }] }]);
  assert.deepEqual(parseMarkdown("one\ntwo\n\nthree"), [{ t: "p", inl: [text("one\ntwo")] }, { t: "p", inl: [text("three")] }]);
});

test("empty and unfinished input is read without an error", () => {
  assert.deepEqual(parseMarkdown(""), []);
  assert.deepEqual(parseMarkdown("**"), [{ t: "p", inl: [text("**")] }]);
  assert.deepEqual(parseMarkdown("```\nnever closed"), [{ t: "pre", s: "never closed" }]);
  assert.deepEqual(parseMarkdown(undefined), []);
});

test("5,000 lines in a fence parse in under 200 ms", () => {
  const body = Array.from({ length: 5000 }, (_, i) => `line ${i} **x** \`y\` [a](https://x.y)`).join("\n");
  const t0 = performance.now();
  const out = parseMarkdown("```\n" + body + "\n```");
  const ms = performance.now() - t0;
  assert.deepEqual(out, [{ t: "pre", s: body }]);
  assert.ok(ms < 200, `took ${ms.toFixed(1)} ms`);
});

test("a very long line of unclosed markers is read in linear time", () => {
  const hostile = "[".repeat(100000) + "*".repeat(100000) + "`".repeat(50001) + "_a".repeat(20000) + "](".repeat(20000);
  const t0 = performance.now();
  const out = parseMarkdown(hostile);
  const ms = performance.now() - t0;
  assert.equal(out.length, 1);
  assert.ok(ms < 500, `took ${ms.toFixed(1)} ms`);
});

test("the companion's source never builds markup from a string or parses HTML, and chat.ts renders a reply through parseMarkdown once", () => {
  const banned = /innerHTML|outerHTML|insertAdjacentHTML|DOMParser/;
  const dir = new URL("../../src/companion/", import.meta.url);
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".ts"));
  assert.ok(files.includes("markdown.ts"), "the Markdown module is in the companion folder");
  for (const f of files) assert.doesNotMatch(code(`companion/${f}`), banned, `companion/${f}`);
  const chat = code("views/chat.ts");
  assert.doesNotMatch(chat, banned, "views/chat.ts");
  assert.equal(chat.split("parseMarkdown(").length - 1, 1, "parseMarkdown is called once in chat.ts");
  assert.match(chat, /if \(m\.content\) col\.append\(h\("div", \{ class: "reply" \}, renderBlocks\(parseMarkdown\(m\.content\), actions\.openUrl\)\)\);/);
});

/** A minimal document for renderBlocks: elements keep their tag, attributes, listeners, children and text, so a test can read what the page would hold. */
function fakeDocument() {
  class FakeNode {
    constructor(tag, text) {
      this.tag = tag;
      this.children = [];
      this.attrs = new Map();
      this.listeners = new Map();
      this.text = text ?? null;
    }
    set textContent(s) {
      this.children = [];
      this.text = s;
    }
    get textContent() {
      return this.text ?? this.children.map((c) => c.textContent).join("");
    }
    setAttribute(k, v) {
      this.attrs.set(k, String(v));
    }
    addEventListener(type, fn) {
      this.listeners.set(type, fn);
    }
    append(...nodes) {
      this.children.push(...nodes);
    }
  }
  return {
    createElement: (tag) => new FakeNode(tag),
    createTextNode: (s) => new FakeNode("#text", s),
    createDocumentFragment: () => new FakeNode("#fragment"),
  };
}

/** Every tag under a node, the node first (a text node is "#text"). */
const tagsUnder = (n) => [n.tag, ...n.children.flatMap(tagsUnder)];

test("renderBlocks: hostile text is text nodes only, and a link has its address as a title, no href, and opens through the island", () => {
  const prev = globalThis.document;
  globalThis.document = fakeDocument();
  try {
    const plain = renderBlocks(parseMarkdown("<img src=x onerror=alert(1)>"), () => assert.fail("no link here"));
    assert.deepEqual(tagsUnder(plain), ["#fragment", "p", "#text"], "markup in a paragraph is one text node");

    const opened = [];
    const linked = renderBlocks(parseMarkdown("[<img onerror=x>](https://x.example)"), (u) => opened.push(u));
    assert.deepEqual(tagsUnder(linked), ["#fragment", "p", "a"], "no img element anywhere; the link's text is no element");
    const a = linked.children[0].children[0];
    assert.equal(a.textContent, "<img onerror=x>");
    assert.equal(a.attrs.get("title"), "https://x.example");
    assert.equal(a.attrs.has("href"), false, "the page never holds a link it could follow");
    let prevented = false;
    a.listeners.get("click")({ preventDefault: () => (prevented = true) });
    assert.equal(prevented, true, "the default is prevented");
    assert.deepEqual(opened, ["https://x.example"], "the click opens the address through the island's own opener");
  } finally {
    globalThis.document = prev;
  }
});
