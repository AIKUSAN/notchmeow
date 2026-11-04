// A reply's light Markdown, read as data. parseMarkdown is pure and total: it never throws and every search is bounded by the work already done (linear
// time, no backtracking regex). renderBlocks builds nodes with createElement and textContent only, so markup in a reply is shown as text.

export type Inline = { t: "text" | "b" | "i" | "code"; s: string } | { t: "link"; s: string; href: string };
export type Block = { t: "p"; inl: Inline[] } | { t: "ul" | "ol"; items: Inline[][] } | { t: "pre"; s: string };

/**
 * The next place of `needle` at or after `from`. Each answer is kept: a later ask from a place up to the kept one (or past a miss) costs nothing, so a line of
 * unclosed markers is searched once per marker kind.
 */
function finder(s: string) {
  const memo = new Map<string, { from: number; at: number }>();
  return (needle: string, from: number): number => {
    const m = memo.get(needle);
    if (m && from >= m.from && (m.at === -1 || from <= m.at)) return m.at;
    const at = s.indexOf(needle, from);
    memo.set(needle, { from, at });
    return at;
  };
}

const isWord = (ch: string | undefined) => ch !== undefined && /[A-Za-z0-9]/.test(ch);
// A link's address: http or https (lower case), then only characters that need no escaping on a command line. One anchored class with one quantifier, so the test is linear.
const WEB_URL = /^https?:\/\/[^\s"<>\\`^|{}\u0000-\u001f\u007f-\u009f]+$/;
const URL_MAX = 2048;
const isWeb = (url: string) => url.length <= URL_MAX && WEB_URL.test(url);

/** One paragraph or item: **bold**, *italic* or _italic_, `code`, [label](url). Anything unmatched is text. */
function inlines(src: string): Inline[] {
  const find = finder(src);
  const out: Inline[] = [];
  let buf = "";
  const flush = () => {
    if (buf) out.push({ t: "text", s: buf });
    buf = "";
  };
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    if (c === "`") {
      const j = find("`", i + 1);
      if (j > i + 1) {
        flush();
        out.push({ t: "code", s: src.slice(i + 1, j) });
        i = j + 1;
        continue;
      }
    } else if (c === "*" && src[i + 1] === "*") {
      const j = find("**", i + 2);
      if (j > i + 2) {
        flush();
        out.push({ t: "b", s: src.slice(i + 2, j) });
        i = j + 2;
        continue;
      }
    } else if (c === "*" || (c === "_" && !isWord(src[i - 1]))) {
      const j = find(c, i + 1);
      if (j > i + 1) {
        flush();
        out.push({ t: "i", s: src.slice(i + 1, j) });
        i = j + 1;
        continue;
      }
    } else if (c === "[") {
      const k = find("]", i + 1);
      if (k > i + 1 && src[k + 1] === "(") {
        const e = find(")", k + 2);
        if (e !== -1) {
          const url = src.slice(k + 2, e);
          if (isWeb(url)) {
            flush();
            out.push({ t: "link", s: src.slice(i + 1, k), href: url });
          } else {
            buf += src.slice(i, e + 1); // a link to anything else is its own text
          }
          i = e + 1;
          continue;
        }
      }
    }
    buf += c;
    i++;
  }
  flush();
  return out;
}

/** The length of a "N. " marker at the start of a line (one to nine digits), or 0. */
function orderedMarker(t: string): number {
  let k = 0;
  while (k < t.length && k < 9 && t[k] >= "0" && t[k] <= "9") k++;
  return k >= 1 && t[k] === "." && t[k + 1] === " " ? k + 2 : 0;
}

export function parseMarkdown(text: string): Block[] {
  const lines = (typeof text === "string" ? text : "").split(/\r?\n/);
  const blocks: Block[] = [];
  let para: string[] = [];
  let list: { t: "ul" | "ol"; items: Inline[][] } | null = null;
  const endPara = () => {
    if (para.length) blocks.push({ t: "p", inl: inlines(para.join("\n")) });
    para = [];
  };
  let i = 0;
  while (i < lines.length) {
    const t = lines[i].trim();
    if (t.startsWith("```")) {
      // A fence: its lines are kept exactly, up to the closing fence (or the end). Its language word is not kept.
      endPara();
      list = null;
      let k = i + 1;
      while (k < lines.length && lines[k].trim() !== "```") k++;
      blocks.push({ t: "pre", s: lines.slice(i + 1, k).join("\n") });
      i = k + 1;
      continue;
    }
    if (t === "") {
      endPara();
      list = null;
      i++;
      continue;
    }
    let hashes = 0;
    while (hashes < t.length && t[hashes] === "#") hashes++;
    if (hashes >= 1 && hashes <= 6 && t[hashes] === " ") {
      endPara();
      list = null;
      blocks.push({ t: "p", inl: [{ t: "b", s: t.slice(hashes + 1).trim() }] });
      i++;
      continue;
    }
    const bullet = t.startsWith("- ") || t.startsWith("* ");
    const marker = bullet ? 2 : orderedMarker(t);
    if (marker > 0) {
      endPara();
      const kind = bullet ? "ul" : "ol";
      if (!list || list.t !== kind) {
        list = { t: kind, items: [] };
        blocks.push(list);
      }
      list.items.push(inlines(t.slice(marker)));
      i++;
      continue;
    }
    list = null;
    para.push(t);
    i++;
  }
  endPara();
  return blocks;
}

function inlineNode(x: Inline, openUrl: (url: string) => void): Node {
  if (x.t === "text") return document.createTextNode(x.s);
  if (x.t === "link") {
    // No href: the link is opened by the island's own openUrl, never by the page. Its address shows as a tooltip (text only, never a link).
    const a = document.createElement("a");
    a.textContent = x.s;
    a.setAttribute("title", x.href);
    a.addEventListener("click", (e) => {
      e.preventDefault();
      openUrl(x.href);
    });
    return a;
  }
  const el = document.createElement(x.t === "b" ? "strong" : x.t === "i" ? "em" : "code");
  el.textContent = x.s;
  return el;
}

export function renderBlocks(blocks: Block[], openUrl: (url: string) => void): DocumentFragment {
  const frag = document.createDocumentFragment();
  for (const b of blocks) {
    if (b.t === "pre") {
      const pre = document.createElement("pre");
      pre.textContent = b.s;
      frag.append(pre);
    } else if (b.t === "p") {
      const p = document.createElement("p");
      p.append(...b.inl.map((x) => inlineNode(x, openUrl)));
      frag.append(p);
    } else {
      const list = document.createElement(b.t);
      for (const item of b.items) {
        const li = document.createElement("li");
        li.append(...item.map((x) => inlineNode(x, openUrl)));
        list.append(li);
      }
      frag.append(list);
    }
  }
  return frag;
}
