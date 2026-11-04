// The Sidekick's notes (sub-project F1, spec "The show gate" and "Dismissal memory"): a recap or a nudge is offered here, and the contract's `shouldShow` says whether it may show now.
// A note that is refused for a reason that can pass (a card is in front, they are typing, another note is up, one showed a minute ago, the rate limit) is kept for a while, 30 s for
// a nudge and 2 minutes for a recap, and shown if the gate opens; then it is dropped without a word. A recap refused because the user is away is kept too; a nudge refused for that reason is dropped at once. A note that is refused for a reason that will not pass soon (the switch is off, the
// kind is muted, the session had its nudge, this away period had its recap) is dropped at once. Nothing here polls and nothing here keeps a timer: the app tells it when the world may
// have changed (`retry`, `stateChanged`), and a held note's time is checked then. Pure: the clock and the island are given. Loaded by the plain-Node checks.

import { HOLD_MS, NUDGE_KINDS, shouldShow } from "./core.ts";
import type { NoteKind, ShowInput, SidekickSettings } from "./core.ts";

/** One note: what is said, and what it is about. It holds only what the contract's lines hold: an agent's name, a project's basename, counts, up to three file basenames. */
export interface Note {
  id: number;
  kind: NoteKind;
  /** The agent a nudge is about (the pill's ID); empty for a recap, which may be about several. */
  agentId: string;
  /** The session a nudge is about (the ledger's key); empty for a recap. */
  key: string;
  /** The words, one line each. A recap has up to three lines and "+N more"; a nudge has one. */
  lines: string[];
  /** The facts the lines were written from (the recap's `facts`, a nudge's agent and numbers): the only thing a local model may be given. */
  facts: unknown[];
  /** The moment the user left (a recap only). */
  awaySince: number | null;
}

/** What a caller offers: a note without its ID, which the notes give. */
export type NoteDraft = Omit<Note, "id">;

/** What the gate needs to know about the world, asked at the moment it decides. */
export interface World {
  /** The agent is rate-limited (the cat already shows it). */
  ratelimit(): boolean;
  /** An approval or a question is in front of the user. */
  card(): "approval" | "question" | null;
  /** The card of the request this nudge is about is on screen. */
  ownCard(): boolean;
  /** The user is typing in the island. */
  typing(): boolean;
  /** The user is away. */
  away(): boolean;
  /** This note is on screen now: the island is open on the Sidekick's view with it. */
  onScreen(id: number): boolean;
}

export interface NotesEnv {
  now(): number;
  settings(): SidekickSettings;
  world: World;
  /** The session of a nudge has had its nudge already. */
  nudged(key: string): boolean;
  /** Opens the island on the note, through the island's own peek. */
  present(note: Note): void;
  /** A note was shown: a nudge's session is marked as nudged. */
  shown(note: Note): void;
  /** A held note ran out of time and was dropped (optional: nothing needs to hear it). */
  dropped?(note: Note): void;
  /** A note that was on screen and never seen was folded away by the island: it was not given. */
  folded(note: Note): void;
  /** A note that waited is still true when the gate opens (a nudge about a loop that has since ended is not). A recap is always true. */
  valid(note: Note): boolean;
  /** The words of the note on screen changed in place. */
  updated(note: Note): void;
  /** One more dismissal of a kind (a click on Not now, OK or ×). */
  dismissed(kind: NoteKind): void;
}

/** The refusals that can pass: the note is kept, up to `HOLD_MS`. Away is one only for a recap: a nudge that fell due while the user was away is dropped (the recap covers it). */
const HOLDABLE = new Set(["ratelimit", "card", "typing", "busy", "recent"]);
const holdable = (note: { kind: NoteKind }, reason: string): boolean => HOLDABLE.has(reason) || (reason === "away" && note.kind === "recap");

const holdFor = (note: { kind: NoteKind }): number => (note.kind === "recap" ? HOLD_MS.recap : HOLD_MS.nudge);
/** A recap first, then the nudges in the contract's order. */
const rank = (note: { kind: NoteKind }): number => (note.kind === "recap" ? -1 : NUDGE_KINDS.indexOf(note.kind));

export class Notes {
  private readonly env: NotesEnv;
  private seq = 0;
  private held: { note: Note; since: number }[] = [];
  private visible: { note: Note; seen: boolean } | null = null;
  private lastShownAt: number | null = null;
  private lastRecapFor: number | null = null;
  private presenting = false;

  constructor(env: NotesEnv) {
    this.env = env;
  }

  /** The note on screen, if one is. */
  get current(): Note | null {
    return this.visible?.note ?? null;
  }

  /** Notes waiting for the gate. */
  get waiting(): readonly Note[] {
    return this.held.map((h) => h.note);
  }

  /** A note is offered. It shows now, is kept for a while, or is dropped; the answer is the gate's reason. */
  offer(draft: NoteDraft): string {
    const note: Note = { ...draft, id: ++this.seq };
    const g = this.gate(note);
    if (g.show) {
      this.show(note);
      return "ok";
    }
    if (holdable(note, g.reason) && !this.held.some((h) => h.note.kind === note.kind && h.note.key === note.key)) this.held.push({ note, since: this.env.now() });
    return g.reason;
  }

  /** The world may have changed (a card hid, the user came back, the switch changed): held notes that ran out of time go, and the first that may show does. */
  retry(): void {
    const now = this.env.now();
    this.held = this.held.filter((h) => {
      if (now - h.since <= holdFor(h.note)) return true;
      this.env.dropped?.(h.note);
      return false;
    });
    for (const h of [...this.held].sort((a, b) => rank(a.note) - rank(b.note))) {
      if (!this.gate(h.note).show) continue;
      this.held = this.held.filter((x) => x !== h);
      // It waited: it must still be true now. One that is not is forgotten, not shown late.
      if (!this.env.valid(h.note)) continue;
      this.show(h.note);
      return;
    }
  }

  /** The words of the note on screen change in place (the waiting nudge once the app has given up on the request; a local model's nicer sentence). Not a second note. */
  reword(id: number, lines: string[]): void {
    const v = this.visible;
    if (!v || v.note.id !== id || v.note.lines.join("\n") === lines.join("\n")) return;
    v.note = { ...v.note, lines };
    this.env.updated(v.note);
  }

  /** The app's state changed. A note that was on screen and is not now was folded away unseen: that is no dismissal. Held notes get another look. */
  stateChanged(): void {
    if (this.presenting) return;
    if (this.visible && !this.env.world.onScreen(this.visible.note.id)) {
      const v = this.visible;
      this.visible = null;
      if (!v.seen) this.env.folded(v.note);
    }
    if (this.held.length) this.retry();
  }

  /** A click on Not now, OK or ×: one more dismissal of the note's kind, and the note is gone. The held notes are not looked at here: the island collapses first (`retry` after that). */
  dismiss(): void {
    const v = this.visible;
    if (!v) return;
    this.visible = null;
    this.env.dismissed(v.note.kind);
  }

  /** The pointer is over the island while the note is up: it has been seen, and a recap no longer replaces it. */
  hovered(): void {
    if (this.visible) this.visible.seen = true;
  }

  /** The switch went off: nothing is waiting any more. */
  clear(): void {
    this.held = [];
  }

  private gate(note: Note) {
    const s = this.env.settings(), w = this.env.world, now = this.env.now();
    const input: ShowInput = {
      on: s.on, kind: note.kind, dismissals: s.dismissals, away: w.away(), ratelimit: w.ratelimit(), card: w.card(), ownCard: w.ownCard(), inputFocused: w.typing(),
      visible: this.visible ? { kind: this.visible.note.kind, seen: this.visible.seen } : null, lastShownAt: this.lastShownAt, now,
      nudged: note.key !== "" && this.env.nudged(note.key), recapGiven: note.kind === "recap" && note.awaySince !== null && note.awaySince === this.lastRecapFor,
    };
    return shouldShow(input);
  }

  private show(note: Note): void {
    this.visible = { note, seen: false };
    this.lastShownAt = this.env.now();
    if (note.kind === "recap") this.lastRecapFor = note.awaySince;
    this.presenting = true;
    try {
      this.env.shown(note);
      this.env.present(note);
    } finally {
      this.presenting = false;
    }
  }
}
