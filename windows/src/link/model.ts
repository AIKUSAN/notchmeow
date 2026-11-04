// The link as the page holds it (sub-project G2): the last snapshot Rust sent, and the few rules the page applies to it. The service, the keys, the sockets and the files are Rust's
// (src-tauri/src/link/); the page holds what to draw and never a key, an address or a path. Pure and DOM-free: the backend is handed in, so the plain-Node checks fake it.
//
// A snapshot is everything the page needs, whole, every time something changes. The page cleans what it is given (`cleanSnapshot`): a value of a shape it does not know becomes "nothing"
// and never throws, so a newer Rust cannot break an older page.

export type LinkRowState = "pairedOnline" | "pairedOffline" | "available";
export type LinkCardKind = "pair" | "offer" | "receiving" | "result";

export interface LinkRow {
  id: string;
  name: string;
  state: LinkRowState;
}

/** One card on the island. `key` says what it is about; a click carries `{kind, key}` back so that Rust acts only on the card the click was meant for. */
export interface LinkCard {
  kind: LinkCardKind;
  key: string;
  /** pair: the six digits. */
  code?: string;
  /** pair, offer, receiving: the other machine's authenticated name. */
  peer?: string;
  /** pair: this user has answered. */
  answered?: boolean;
  /** offer, receiving: the sanitized name, the one that will be saved. */
  name?: string;
  size?: number;
  received?: number;
  /** result. */
  title?: string;
  detail?: string;
  /** result: a file was saved, so "Show in folder" is there. */
  canReveal?: boolean;
}

export interface LinkSnapshot {
  visible: boolean;
  name: string;
  listening: boolean;
  /** A sentence for Settings → Devices when the listener or the credential store could not do what was asked. */
  problem: string | null;
  /** A one-line note after a pairing that did not happen. */
  note: string | null;
  rows: LinkRow[];
  card: LinkCard | null;
  /** One line for the shelf while this machine sends ("Sending a.pdf to Desk PC, 45 %"). */
  sendStatus: string | null;
  sending: boolean;
  /** Where received files go, to show. */
  folder: string;
}

export const LINK_EMPTY: LinkSnapshot = { visible: false, name: "", listening: false, problem: null, note: null, rows: [], card: null, sendStatus: null, sending: false, folder: "" };

const ROW_STATES: readonly string[] = ["pairedOnline", "pairedOffline", "available"];
const CARD_KINDS: readonly string[] = ["pair", "offer", "receiving", "result"];

const text = (v: unknown, max = 2000): string | undefined => (typeof v === "string" ? v.slice(0, max) : undefined);
const count = (v: unknown): number | undefined => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : undefined);

function cleanCard(raw: unknown): LinkCard | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.kind !== "string" || !CARD_KINDS.includes(r.kind) || typeof r.key !== "string") return null;
  const card: LinkCard = { kind: r.kind as LinkCardKind, key: r.key.slice(0, 2000) };
  const set = <K extends keyof LinkCard>(k: K, v: LinkCard[K] | undefined) => {
    if (v !== undefined) card[k] = v;
  };
  set("code", text(r.code, 12));
  set("peer", text(r.peer, 200));
  set("answered", typeof r.answered === "boolean" ? r.answered : undefined);
  set("name", text(r.name, 400));
  set("size", count(r.size));
  set("received", count(r.received));
  set("title", text(r.title, 200));
  set("detail", text(r.detail, 600));
  set("canReveal", typeof r.canReveal === "boolean" ? r.canReveal : undefined);
  return card;
}

/** Whatever Rust sent, as a snapshot: unknown shapes are dropped, never thrown at. */
export function cleanSnapshot(raw: unknown): LinkSnapshot {
  if (!raw || typeof raw !== "object") return LINK_EMPTY;
  const r = raw as Record<string, unknown>;
  const rows: LinkRow[] = [];
  if (Array.isArray(r.rows)) {
    for (const x of r.rows) {
      const o = x as Record<string, unknown> | null;
      if (o && typeof o.id === "string" && typeof o.name === "string" && typeof o.state === "string" && ROW_STATES.includes(o.state)) {
        rows.push({ id: o.id, name: o.name.slice(0, 200), state: o.state as LinkRowState });
      }
    }
  }
  return {
    visible: r.visible === true,
    name: text(r.name, 200) ?? "",
    listening: r.listening === true,
    problem: text(r.problem, 600) ?? null,
    note: text(r.note, 300) ?? null,
    rows,
    card: cleanCard(r.card),
    sendStatus: text(r.sendStatus, 600) ?? null,
    sending: r.sending === true,
    folder: text(r.folder, 600) ?? "",
  };
}

/** The card a click is meant for: what the user saw. */
export interface ShownRef {
  kind: LinkCardKind;
  key: string;
}

export const shownOf = (card: LinkCard): ShownRef => ({ kind: card.kind, key: card.key });

/** A card with buttons the user is about to press holds the island open; a result is only read. */
export const holdsIsland = (card: LinkCard | null): boolean => card !== null && card.kind !== "result";

/** An offer waits for a click: an alert like an approval (the desktop cat flies to the notch for it, the cats do not sleep through it). */
export const offerPending = (card: LinkCard | null): boolean => card?.kind === "offer";

/** What the island does when the card changes. */
export interface CardTransition {
  /** Open the island on the link view. */
  alert: boolean;
  /** Keep it open against the delayed collapse. */
  hold: boolean;
  /** Let it auto-close again. */
  release: boolean;
  /** Close it: the card went and the link view was showing. */
  collapse: boolean;
}

/** A new card, or a card of another kind, opens the island (the quiet period of Rust's `CardRules` covers the click); the same kind again (the user's own answer, a progress tick) does not. */
export function cardTransition(prev: LinkCard | null, next: LinkCard | null, linkViewShowing: boolean): CardTransition {
  const changedKind = next !== null && (prev === null || prev.kind !== next.kind);
  return { alert: changedKind, hold: holdsIsland(next), release: holdsIsland(prev) && !holdsIsland(next), collapse: next === null && linkViewShowing };
}

/** Which machines the shelf offers: the paired ones, online first (Rust already orders the rows that way). */
export const sendTargets = (rows: readonly LinkRow[]): LinkRow[] => rows.filter((r) => r.state === "pairedOnline");

/** "To a device" shows when the link is on or a machine is paired. */
export const showDeviceButton = (s: LinkSnapshot): boolean => s.visible || s.rows.some((r) => r.state !== "available");

/** What the page can ask of the service. Every call only posts a request; the answer is the next snapshot. */
export interface LinkBackend {
  state(): Promise<LinkSnapshot>;
  onSnapshot(cb: (s: LinkSnapshot) => void): () => void;
  setVisible(on: boolean): void;
  setName(name: string): Promise<boolean>;
  setDevicesOpen(open: boolean): void;
  setShelfOpen(open: boolean): void;
  pair(id: string): void;
  answerPair(yes: boolean, shown: ShownRef | null): void;
  respondOffer(accept: boolean, shown: ShownRef | null): void;
  cancelReceiving(shown: ShownRef | null): void;
  dismiss(shown: ShownRef | null): void;
  forget(id: string): void;
  /** Shelf ids, never paths: Rust finds the files. */
  send(ids: string[], to: string): void;
  cancelSending(): void;
  revealResult(): void;
  revealFolder(): void;
}

/** The page's link: the last snapshot, the backend, and who is told when it changes. */
export class LinkStore {
  snapshot: LinkSnapshot = LINK_EMPTY;
  backend: LinkBackend | null = null;
  private stop: (() => void) | null = null;
  private readonly changed: () => void;
  constructor(changed: () => void = () => {}) {
    this.changed = changed;
  }

  /** Starts hearing the backend. The first state is read at once; after that the backend pushes. Returns what changed from, for the island's card rule. */
  attach(backend: LinkBackend, onChange?: (prev: LinkSnapshot, next: LinkSnapshot) => void): void {
    this.stop?.();
    this.backend = backend;
    // The reply to state() travels another way than the pushes and can arrive after a newer push: once one push has come, the reply is older than what is kept and is dropped.
    let pushed = false;
    this.stop = backend.onSnapshot((s) => {
      pushed = true;
      this.apply(s, onChange);
    });
    void backend.state().then((s) => { if (!pushed) this.apply(s, onChange); }).catch(() => {});
  }

  apply(next: LinkSnapshot, onChange?: (prev: LinkSnapshot, next: LinkSnapshot) => void): void {
    const prev = this.snapshot;
    if (JSON.stringify(prev) === JSON.stringify(next)) return;
    this.snapshot = next;
    onChange?.(prev, next);
    this.changed();
  }

  get offerPending(): boolean {
    return offerPending(this.snapshot.card);
  }
}
