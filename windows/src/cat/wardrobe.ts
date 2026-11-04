// The wardrobe's rules (sub-project I): the 18 selection IDs and their clean-up, Auto's calendar, and who wears an outfit. A port of the first half of "The wardrobe (sub-project I)"
// in design/prototype/cat-core.js, the tie-breaker (fixture tests/fixtures/cat/wardrobe-cases.json; docs/CAT-CONTRACT.md "The wardrobe (I-0)"). Pure: numbers and strings in, strings out,
// no clock and no canvas, so the plain-Node checks (npm run check:cat) can load it. The shapes an outfit is made of are in outfit.ts; the Auto timer is island/wardrobe.ts.

/** The 18 selection IDs in the order of the grid, the menus and the settings: frozen contract values, because they are stored. */
export const OUTFIT_IDS = [
  "auto", "none", "partyhat", "santahat", "witchhat", "bunnyears", "sunglasses", "beanie", "bow", "scarf", "roundglasses", "crown", "bell", "bandana", "fishclip", "flower", "shrimpclip", "blossomclip",
] as const;
export type OutfitId = (typeof OUTFIT_IDS)[number];
/** The 16 outfits that are drawn: everything but the two choices. */
export const OUTFIT_DRAWN: readonly OutfitId[] = OUTFIT_IDS.slice(2);
export type DrawnOutfit = Exclude<OutfitId, "auto" | "none">;
export const DEFAULT_OUTFIT: OutfitId = "auto";

/** The names the UI shows, by ID. */
export const OUTFIT_NAMES: Readonly<Record<OutfitId, string>> = {
  auto: "Auto", none: "None", partyhat: "Party hat", santahat: "Santa hat", witchhat: "Witch hat", bunnyears: "Bunny ears", sunglasses: "Sunglasses", beanie: "Beanie", bow: "Bow",
  scarf: "Scarf", roundglasses: "Round glasses", crown: "Crown", bell: "Bell", bandana: "Bandana", fishclip: "Fish clip", flower: "Flower", shrimpclip: "Shrimp clip", blossomclip: "Peach-blossom clip",
};

/** The grid's rows: the two choices, then the four groups with their headings. */
export const OUTFIT_GROUPS: readonly { id: string; name: string; ids: readonly OutfitId[] }[] = [
  { id: "choice", name: "", ids: ["auto", "none"] },
  { id: "seasonal", name: "Seasonal", ids: ["partyhat", "santahat", "witchhat", "bunnyears", "sunglasses"] },
  { id: "everyday", name: "Everyday", ids: ["beanie", "bow", "scarf", "roundglasses", "crown"] },
  { id: "extras", name: "Cat extras", ids: ["bell", "bandana", "fishclip", "flower"] },
  { id: "own", name: "The cats' own", ids: ["shrimpclip", "blossomclip"] },
];

const isPlain = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

/** A stored outfit to an ID: exactly one of the 18, as written (lowercase, no trimming); anything else, or no string at all, is `auto`. */
export const outfitIdOf = (v: unknown): OutfitId => (typeof v === "string" && (OUTFIT_IDS as readonly string[]).includes(v) ? (v as OutfitId) : DEFAULT_OUTFIT);

/** What Settings stores for the wardrobe, cleaned: `{outfit}`. `raw` is the stored `cat` block as plain JSON; it reads only `outfit`. Never throws. */
export const cleanWardrobeSettings = (raw: unknown): { outfit: OutfitId } => ({ outfit: outfitIdOf(isPlain(raw) ? raw.outfit : undefined) });

/** Gregorian Easter Sunday of a year from 1583 to 9999 as {month, day} (the Meeus/Jones/Butcher computation); null for any other year. */
export function easterOf(year: unknown): { month: number; day: number } | null {
  if (typeof year !== "number" || !Number.isInteger(year) || year < 1583 || year > 9999) return null;
  const a = year % 19, b = Math.floor(year / 100), c = year % 100, d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30, i = Math.floor(c / 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451), n = h + l - 7 * m + 114;
  return { month: Math.floor(n / 31), day: (n % 31) + 1 };
}

/** Days since 1970-01-01 of a calendar date, from the date numbers alone (no clock, no time zone), so a difference of two dates can never be shifted by daylight saving. */
const owDays = (y: number, m: number, d: number): number => {
  const yy = m <= 2 ? y - 1 : y, era = Math.floor(yy / 400), yoe = yy - era * 400, doy = Math.floor((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
  return era * 146097 + (yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy) - 719468;
};
const owValid = (y: unknown, m: unknown, d: unknown): boolean =>
  typeof y === "number" && typeof m === "number" && typeof d === "number" && Number.isInteger(y) && Number.isInteger(m) && Number.isInteger(d) && y >= 1 && y <= 9999 && m >= 1 && m <= 12 && d >= 1 &&
  d <= [31, y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];

/**
 * What Auto wears on a local date (year, month, day as numbers; the northern calendar, the same for everyone). The first rule that matches wins, and the order is the contract:
 *   1 Dec 31 to Jan 2 partyhat   2 Dec 1 to Dec 26 santahat   3 Oct 1 to Nov 1 witchhat   4 Good Friday to Easter Monday (Easter -2 to +1) bunnyears   5 Jun 21 to Aug 31 sunglasses
 * Anything else, and a date that is not a real date, is `none`.
 */
export function autoOutfitFor(y: unknown, m: unknown, d: unknown): OutfitId {
  if (!owValid(y, m, d)) return "none";
  const Y = y as number, M = m as number, Dd = d as number;
  if ((M === 12 && Dd === 31) || (M === 1 && Dd <= 2)) return "partyhat";
  if (M === 12 && Dd <= 26) return "santahat";
  if (M === 10 || (M === 11 && Dd === 1)) return "witchhat";
  const E = easterOf(Y);
  if (E) {
    const k = owDays(Y, M, Dd) - owDays(Y, E.month, E.day);
    if (k >= -2 && k <= 1) return "bunnyears";
  }
  if ((M === 6 && Dd >= 21) || M === 7 || M === 8) return "sunglasses";
  return "none";
}

/** The outfit to draw: the stored choice cleaned, with `auto` replaced by what autoOutfitFor says for the date (`none` when nothing is worn). Never `auto`. */
export const resolveOutfit = (id: unknown, y: unknown, m: unknown, d: unknown): OutfitId => {
  const o = outfitIdOf(id);
  return o === "auto" ? autoOutfitFor(y, m, d) : o;
};

/** The roles a drawn cat can have. The views map to them: the island's big cats and the desktop cat are `big`, the pills', the mini row's and the grid's cats `small`, the kittens `kitten`. */
export const OUTFIT_ROLES = ["big", "small", "kitten"] as const;
export type OutfitRole = (typeof OUTFIT_ROLES)[number];
/** Who wears the outfit: the big-cat role, at every size (the compact notch's Ø20 cat included). Anything else, and anything that is not a role, is bare. */
export const outfitWorn = (role: unknown): boolean => role === "big";
