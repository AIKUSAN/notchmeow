// Dev server only (sub-project G2): the states of the link worth looking at, as snapshots, for the `?dev` page's Link panel and for `settings.html?linkdev=<state>`. Sample names only. Nothing
// here is imported by a release build: both callers load it behind `import.meta.env.DEV`.

import { mockLinkBackend } from "./mock.ts";
import type { LinkCard, LinkRow, LinkSnapshot } from "./model.ts";

export const ID = { mac: "a1".repeat(16), desk: "b2".repeat(16), laptop: "c3".repeat(16), netbook: "d4".repeat(16) } as const;

export const ROWS: Record<string, LinkRow[]> = {
  none: [],
  two: [
    { id: ID.mac, name: "Sam's MacBook Pro", state: "pairedOnline" },
    { id: ID.laptop, name: "Studio laptop", state: "pairedOnline" },
    { id: ID.netbook, name: "Old netbook", state: "pairedOffline" },
    { id: ID.desk, name: "Desk PC", state: "available" },
  ],
  offline: [{ id: ID.netbook, name: "Old netbook", state: "pairedOffline" }],
};

export const CARDS: Record<string, LinkCard> = {
  pair: { kind: "pair", key: "483291|Sam's MacBook Pro", code: "483291", peer: "Sam's MacBook Pro", answered: false },
  pairAnswered: { kind: "pair", key: "483291|Sam's MacBook Pro", code: "483291", peer: "Sam's MacBook Pro", answered: true },
  offer: { kind: "offer", key: `${ID.mac}|t1`, name: "Quarterly report.pdf", size: 2_400_000, peer: "Sam's MacBook Pro" },
  offerLong: { kind: "offer", key: `${ID.mac}|t2`, name: "A very long file name that goes on and on and on for the whole width of the card, final version 7.docx", size: 48_000_000, peer: "Sam's MacBook Pro with a long machine name" },
  receiving0: { kind: "receiving", key: `${ID.mac}|t1`, name: "Quarterly report.pdf", size: 2_400_000, received: 0, peer: "Sam's MacBook Pro" },
  receiving45: { kind: "receiving", key: `${ID.mac}|t1`, name: "Quarterly report.pdf", size: 2_400_000, received: 1_080_000, peer: "Sam's MacBook Pro" },
  receiving100: { kind: "receiving", key: `${ID.mac}|t1`, name: "Quarterly report.pdf", size: 2_400_000, received: 2_400_000, peer: "Sam's MacBook Pro" },
  received: { kind: "result", key: "Received|Saved as Quarterly report.pdf", title: "Received", detail: "Saved as Quarterly report.pdf in Downloads/NotchMeow.", canReveal: true },
  paired: { kind: "result", key: "Paired|x", title: "Paired", detail: "This computer and Sam's MacBook Pro can now send files to each other.", canReveal: false },
  notPaired: { kind: "result", key: "Not paired|x", title: "Not paired", detail: "The other machine said the codes did not match.", canReveal: false },
  expired: { kind: "result", key: "Offer expired|x", title: "Offer expired", detail: "Nobody answered in 2 minutes, so it was declined.", canReveal: false },
  cancelled: { kind: "result", key: "Transfer cancelled|x", title: "Transfer cancelled", detail: "Nothing was saved.", canReveal: false },
  stopped: { kind: "result", key: "Transfer stopped|x", title: "Transfer stopped", detail: "The connection ended before the file was complete. Nothing was saved.", canReveal: false },
};

/** `settings.html?linkdev=<name>`: off, on, empty, problem, note. */
export const SEEDS: Record<string, Partial<LinkSnapshot>> = {
  off: {},
  on: { visible: true, listening: true, rows: ROWS.two },
  empty: { visible: true, listening: true, rows: ROWS.none },
  problem: { visible: true, listening: false, problem: "This computer could not start listening.", rows: ROWS.offline },
  note: { visible: true, listening: true, rows: ROWS.two, note: "Wait 30 seconds before trying again." },
};

export function devBackend(name: string) {
  return mockLinkBackend(SEEDS[name] ?? SEEDS.on);
}
