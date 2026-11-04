// The shelf contract's three rules in TypeScript (sub-project G1; docs/SHELF-CONTRACT.md, tests/fixtures/shelf/). Pure: no DOM, no Tauri, nothing stored.
// `tests/fixtures/shelf/reference.py` is the tie-breaker; scripts/cat-tests/shelf-rules.test.mjs replays every row of both fixtures through this file.
// The Rust twin for the file on disk is src-tauri/src/shelf.rs (it replays the same rows).

export const SHELF_MAX = 30;
export const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
export const NAME_MAX = 255;
export const LINK_MAX = 8192;
export const NUMBER_MAX = 9007199254740991;

export type Zone = "ask" | "shelf";

/** One thing on the shelf. A copy lives in `shelf/<id>/<name>` and has no link; every other item points at its original by `link` (a path here). */
export interface ShelfItem {
  id: string;
  name: string;
  size: number;
  folder: boolean;
  copy: boolean;
  link?: string;
  addedAt: number;
}

export type AddWord = "added" | "duplicate" | "full" | "invalid";

const own = (o: object, k: string): unknown => (Object.prototype.hasOwnProperty.call(o, k) ? (o as Record<string, unknown>)[k] : undefined);
const isObject = (v: unknown): v is object => typeof v === "object" && v !== null && !Array.isArray(v);

/** Which half of the open island the pointer is in: `x` from the island's left edge, `width` the island's. The centre line is Ask. Null outside the island or for anything that is not a number. */
export function zoneAt(x: unknown, width: unknown): Zone | null {
  for (const v of [x, width]) if (typeof v !== "number" || !Number.isFinite(v) || Math.abs(v) > NUMBER_MAX) return null;
  const px = x as number, w = width as number;
  if (w <= 0 || px < 0 || px > w) return null;
  return px * 2 <= w ? "ask" : "shelf";
}

/** Windows device names, refused as a name's stem or an id (ASCII case-insensitively; the superscript digits are reserved too). */
const RESERVED = new Set(["CON", "PRN", "AUX", "NUL", ...[1, 2, 3, 4, 5, 6, 7, 8, 9].flatMap((n) => [`COM${n}`, `LPT${n}`]), "COM\xb9", "COM\xb2", "COM\xb3", "LPT\xb9", "LPT\xb2", "LPT\xb3"]);
const asciiUpper = (s: string) => s.replace(/[a-z]/g, (c) => c.toUpperCase());
const reserved = (s: string) => RESERVED.has(asciiUpper(s.split(".", 1)[0].replace(/ +$/, "")));
const BAD_NAME_CHAR = /[\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}]/u;
const BAD_LINK_CHAR = /[\x00-\x1f\x7f-\x9f\p{Cs}]/u;
const codePoints = (s: string) => Array.from(s).length;

function nameOk(name: unknown): name is string {
  if (typeof name !== "string") return false;
  const n = codePoints(name);
  if (n < 1 || n > NAME_MAX) return false;
  if (BAD_NAME_CHAR.test(name) || name.includes("/") || name.includes("\\") || /^\.+$/.test(name) || /[. ]$/.test(name)) return false;
  return !reserved(name);
}

/** A whole number from 0 to NUMBER_MAX (5 and 5.0 are the same JSON number), else 0. */
function whole(v: unknown): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > NUMBER_MAX) return 0;
  return v === 0 ? 0 : v;
}

function itemClean(raw: unknown): ShelfItem | null {
  if (!isObject(raw)) return null;
  const id = own(raw, "id"), name = own(raw, "name");
  if (typeof id !== "string" || !ID_RE.test(id) || reserved(id) || !nameOk(name)) return null;
  const copy = own(raw, "copy") === true, folder = own(raw, "folder") === true;
  if (copy && folder) return null; // a folder is only ever a link
  const size = whole(own(raw, "size")), addedAt = whole(own(raw, "addedAt"));
  if (copy) return { id, name, size, folder, copy, addedAt };
  const link = own(raw, "link");
  if (typeof link !== "string" || codePoints(link) < 1 || codePoints(link) > LINK_MAX || BAD_LINK_CHAR.test(link)) return null;
  return { id, name, size, folder, copy, link, addedAt };
}

/** Newest first (stable), then the first of each id (ASCII case-insensitive) and of each link (exact), then the first SHELF_MAX. One pass in sorted order. */
function tidy(items: ShelfItem[]): ShelfItem[] {
  const sorted = [...items].sort((a, b) => b.addedAt - a.addedAt);
  const ids = new Set<string>(), links = new Set<string>(), out: ShelfItem[] = [];
  for (const it of sorted) {
    const idKey = asciiLower(it.id);
    if (ids.has(idKey) || (it.link !== undefined && links.has(it.link))) continue;
    ids.add(idKey);
    if (it.link !== undefined) links.add(it.link);
    out.push(it);
  }
  return out.slice(0, SHELF_MAX);
}
const asciiLower = (s: string) => s.replace(/[A-Z]/g, (c) => c.toLowerCase());

/** The parsed content of shelf.json to the items the shelf holds. Never throws. */
export function shelfClean(raw: unknown): ShelfItem[] {
  if (!isObject(raw)) return [];
  const items = own(raw, "items");
  if (!Array.isArray(items)) return [];
  return tidy(items.map(itemClean).filter((i): i is ShelfItem => i !== null));
}

/** Files dropped on the Shelf half. One word per incoming item; nothing already shelved is ever removed. */
export function shelfAdd(items: unknown, incoming: unknown): { items: ShelfItem[]; results: AddWord[] } {
  const current = shelfClean({ items });
  const ids = new Set(current.map((i) => asciiLower(i.id)));
  const links = new Set(current.flatMap((i) => (i.link !== undefined ? [i.link] : [])));
  const accepted: ShelfItem[] = [], results: AddWord[] = [];
  for (const raw of Array.isArray(incoming) ? incoming : []) {
    const it = itemClean(raw);
    if (it === null) results.push("invalid");
    else if (ids.has(asciiLower(it.id)) || (it.link !== undefined && links.has(it.link))) results.push("duplicate");
    else if (current.length + accepted.length >= SHELF_MAX) results.push("full");
    else {
      accepted.push(it);
      ids.add(asciiLower(it.id));
      if (it.link !== undefined) links.add(it.link);
      results.push("added");
    }
  }
  return { items: tidy([...accepted, ...current]), results };
}

/** The bytes of shelf.json to the items it holds. Unreadable bytes (not UTF-8, a BOM, NaN, text after the value, not an object) are an empty shelf. Never throws. */
export function readShelf(bytes: Uint8Array): ShelfItem[] {
  try {
    const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
    return shelfClean(JSON.parse(text));
  } catch {
    return [];
  }
}
