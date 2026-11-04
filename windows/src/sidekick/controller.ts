// The Sidekick (sub-project F1): the glue between the hook events, the ledger and the pure rules of src/sidekick/core.ts. The rules decide everything; this class only
// feeds them and carries out the answers. It never blocks a hook, never answers an approval and never reads a transcript. Loaded by the plain-Node checks: it knows nothing of
// the DOM, the island or Tauri (the island gives it what it needs through `SidekickEnv`).

import { SessionLedger } from "./ledger.ts";
import { Notes } from "./notes.ts";
import type { Note, World } from "./notes.ts";
import { Presence } from "./presence.ts";
import type { Return } from "./presence.ts";
import { STUCK, agentName, markNudged, matchStatusQuestion, nudgeText, recapOf, statusOf, stuckStep } from "./core.ts";
import type { Ledger, Nudge, NoteKind, Platform, Recap, SidekickSettings, StatusQuestion, StuckContext } from "./core.ts";
import { mutedKinds, withDismissed } from "./settings.ts";
import { StuckClock } from "./stuckclock.ts";
import { explainRequest } from "./explain.ts";
import { nicerLines } from "./voice.ts";
import type { OneShot } from "./voice.ts";
import type { Explained } from "./core.ts";

/** The parts of the world a nudge depends on, as one word: when it changes, the rules are asked again. */
const ctxKey = (c: StuckContext): string => `${c.ratelimit === true}|${c.away === true}|${c.cardShown === true}`;

/** The earlier of two deadlines; null is no deadline. */
const earlier = (a: number | null, b: number | null): number | null => (a === null ? b : b === null ? a : Math.min(a, b));

/** The idle time is read at most this often (ms), however many hook events arrive. */
export const SAMPLE_GAP_MS = 5000;
/** An idle reading that has not answered by then is no reading (ms): the OS may never say, and the next reading must still be possible. */
export const IDLE_TIMEOUT_MS = 3000;

/** What the Sidekick needs from the world. */
export interface SidekickEnv {
  /** Wall-clock milliseconds: it keeps counting while the machine sleeps, as a monotonic clock may not. */
  now(): number;
  platform: Exclude<Platform, "mac">;
  /** The user's home folder, to read `~` in a path. Used for the risk label only and never shown. */
  home: string;
  /** Seconds since the user's last keyboard or mouse input, or null where the system does not say. Asked only when something needs it, never on a timer. */
  idleSeconds(): Promise<number | null>;
  /** The Sidekick settings as stored, clean: asked at the moment of every decision, so a change in Settings counts at once. */
  settings(): SidekickSettings;
  /** Stores new Sidekick settings (the dismissal counts changed). */
  saveSettings(next: SidekickSettings): void;
  /** What the gate asks of the island: whether a card is in front, whether the user is typing, whether a note is on screen. */
  world: Omit<World, "away">;
  /** Opens the island on a note, through the island's own peek (the view the finished task uses). */
  present(note: Note): void;
  /** The words of the note on screen changed in place. */
  updated(note: Note): void;
  /** One short question to a model on this computer (Rust's `ai_oneshot`): one line, or null. Used only for a note's nicer wording, only when Settings allows it. */
  oneshot: OneShot;
  /** The pointer is over the island: a nicer sentence does not swap in under it. */
  hovering(): boolean;
  /** One timer at a time is all the Sidekick ever asks for (the stuck clock). */
  timer: { set(fn: () => void, ms: number): number; clear(id: number): void };
  /** Resolves after `ms`, and clears its timer when `signal` aborts: the timeout of an idle reading only, never a poll. The Sidekick aborts it when the reading settles. */
  wait(ms: number, signal: AbortSignal): Promise<void>;
  /** The session's live stepped-back mark's end on the Sidekick's clock (focus awareness), or null: the stuck rules hold its wait until then. Optional, so the hand-built envs need not give it. */
  stepBackEnd?(sessionId: string): number | null;
  /** The earliest live stepped-back mark's end on the Sidekick's clock, or null: the clock wakes then, once per mark (the Mac's `Env.focusLapseAt`). */
  focusLapseAt?(): number | null;
  /** A mark ran out: the app redraws its pill (the dot and the note are read when drawn). */
  focusLapsed?(): void;
}

export class Sidekick {
  readonly ledger = new SessionLedger();
  readonly presence = new Presence();
  /** Told, once each, when the user comes back from being away (the recap listens). */
  readonly onReturn: Array<(r: Return) => void> = [];
  /** The recaps and nudges waiting for the gate or on screen. */
  readonly notes: Notes;
  /** The stuck clock: one one-shot timer, set to the nearest deadline of the rules that wait, and not set while nothing is live. */
  readonly clock: StuckClock;
  private lastCtx = "";
  /** Nudges that fell due while the user was away, by what they were about: dropped, never shown later. A new event for the session is a new thing, and lifts it. */
  private readonly droppedWhileAway = new Set<string>();
  private readonly env: SidekickEnv;
  private lastSampleAt = Number.NEGATIVE_INFINITY;
  private sampling = false;
  /** A forced reading (an unlock, a wake, the display on) asked while another is in flight: it is taken once that one is done. */
  private queued = false;
  /** The nearest time a live stepped-back mark runs out (`SidekickEnv.focusLapseAt`), or null. `evaluate` sets it, so the clock wakes then and the app is told once. */
  private focusLapseAt: number | null = null;

  constructor(env: SidekickEnv) {
    this.env = env;
    this.notes = new Notes({
      now: () => env.now(),
      settings: () => env.settings(),
      world: { ...env.world, away: () => this.presence.away },
      nudged: (key) => this.ledger.snapshot.sessions.some((s) => s.key === key && s.nudgedAt !== null),
      present: (note) => env.present(note),
      shown: (note) => {
        if (note.kind !== "recap") this.ledger.markNudged(note.key, env.now());
        void this.polish(note);
      },
      folded: (note) => {
        // Shown, then folded away before the user saw it: not given, so its session may be nudged again.
        if (note.kind !== "recap") this.ledger.unmarkNudged(note.key);
      },
      dismissed: (kind) => this.dismissed(kind),
      valid: (note) => this.stillTrue(note),
      updated: (note) => env.updated(note),
    });
    this.clock = new StuckClock({ set: (fn, ms) => env.timer.set(fn, ms), clear: (id) => env.timer.clear(id), now: () => env.now() }, () => this.evaluate());
    // First: a nudge that fell due while the user was away is dropped (the recap covers it), then the recap.
    this.onReturn.push(() => this.dropDueWhileAway());
    this.onReturn.push((r) => this.recap(r));
  }

  /**
   * One hook event, fed before anything else can refuse it (a request displaced by the one card, or declined for another agent, is still counted). It must never throw into the
   * island's hook handler: a failure here is the Sidekick's own and costs it one event.
   */
  hook(payload: unknown): void {
    try {
      this.ledger.feed(payload, this.env.now());
    } catch {
      // The sidekick never breaks the island.
    }
    this.evaluate();
    void this.sampleIdle();
  }

  /**
   * How risky a permission request looks and the sentence for it (the card's grey line and orange badge). It labels only. It never throws: a request it cannot read is
   * `unsure`, which is medium.
   */
  explain(tool: string, input: unknown, cwd: string): Explained {
    try {
      return explainRequest(tool, input, cwd, this.env.home);
    } catch {
      return explainRequest("", null, "", "");
    }
  }

  /**
   * The local voice. The template is on screen already. If a model on this computer finds a nicer sentence for a line and the contract's check accepts it, it crossfades in, once, and
   * only if the note is still the one on screen and the pointer is not over it. After that nothing changes. A permission line never comes here.
   */
  private async polish(note: Note): Promise<void> {
    if (!this.env.settings().local) return;
    // Never inside the call that shows the note: the question starts a moment later.
    await Promise.resolve();
    try {
      const lines = await nicerLines(this.env.oneshot, note.lines, note.facts);
      if (lines === null || this.notes.current?.id !== note.id || this.env.hovering()) return;
      this.notes.reword(note.id, lines);
    } catch {
      // The template stands.
    }
  }

  /** A nicer wording for the lines of an answer in the chat (the status card), by the same rules; null when there is none. */
  async polishLines(lines: readonly string[], facts: readonly unknown[]): Promise<string[] | null> {
    if (!this.env.settings().local) return null;
    try {
      return await nicerLines(this.env.oneshot, lines, facts);
    } catch {
      return null;
    }
  }

  /** Is this message the question "What's Claude doing?" (the contract's `matchStatusQuestion`: the whole short message, nothing more)? */
  matchStatus(text: string): StatusQuestion {
    try {
      return matchStatusQuestion(text);
    } catch {
      return { matched: false, agentId: null };
    }
  }

  /** What the agents are doing, from the ledger, in the same words as the recap: every live session, or the one agent. Answered here and never sent anywhere. */
  status(agentId: string | null): Recap {
    return statusOf({ now: this.env.now(), sessions: this.ledger.snapshot.sessions }, agentId ?? undefined);
  }

  /** The user clicked Allow or Deny on a card. */
  approvalAnswered(agentId: string, sessionId: string): void {
    try {
      this.ledger.answered(agentId, sessionId, this.env.now());
    } catch {
      // Same.
    }
  }

  /**
   * The platform told the app that the user went away or came back: a lock, an unlock, a sleep, a wake, the display off or on. An unlock, a wake or the display coming on reads the
   * idle time at once, because the user may be at the keyboard already.
   */
  presenceSignal(word: unknown): void {
    try {
      const back = this.presence.signal(word, this.env.now());
      if (back) this.back(back);
    } catch {
      // Same.
    }
    // Away or back changes what may be said, and a one-shot timer does not fire while the machine sleeps: the rules are asked again at once.
    this.evaluate();
    if (word === "unlock" || word === "wake" || word === "displayOn") void this.sampleIdle(true);
  }

  /**
   * An idle sample. It is taken at most every 5 s (`force` skips the wait: an unlock) and only while it can matter: an agent is running, or the user is away. Nothing calls this on
   * a timer: a hook event, the island opening and an unlock do.
   */
  async sampleIdle(force = false): Promise<void> {
    if (this.sampling) {
      if (force) this.queued = true;
      return;
    }
    const now = this.env.now();
    if (!force && now - this.lastSampleAt < SAMPLE_GAP_MS) return;
    if (this.ledger.live.length === 0 && !this.presence.away) return;
    this.sampling = true;
    this.lastSampleAt = now;
    const timeout = new AbortController();
    try {
      // A reading that has not answered by the timeout is no reading (null); the flag is cleared all the same.
      const seconds = await Promise.race([this.env.idleSeconds(), this.env.wait(IDLE_TIMEOUT_MS, timeout.signal).then(() => null)]);
      const back = this.presence.sample(seconds, this.env.now());
      if (back) this.back(back);
      // Away or back changes what the rules say, and the armed clock must follow it: no timer runs while away.
      this.evaluate();
    } catch {
      // A sample that fails is no sample.
    } finally {
      // The reading settled, one way or the other: its timeout is cleared, so no timer outlives it.
      timeout.abort();
      this.sampling = false;
      if (this.queued) {
        this.queued = false;
        void this.sampleIdle(true);
      }
    }
  }

  /** The island opened (compact or open): a good moment to look at the idle time. */
  islandOpened(): void {
    void this.sampleIdle();
  }

  /** The user came back: if an agent did something while they were away, a recap is offered to the gate. */
  private recap(r: Return): void {
    const now = this.env.now();
    const recap = recapOf({ awaySince: r.awaySince, now, sessions: this.ledger.snapshot.sessions });
    if (!recap) return;
    this.notes.offer({ kind: "recap", agentId: "", key: "", lines: recap.lines.map((l) => (/^\+\d+ more$/.test(l) ? "…" : l)), facts: recap.facts, awaySince: r.awaySince });
  }

  private dismissed(kind: NoteKind): void {
    this.env.saveSettings(withDismissed(this.env.settings(), kind));
  }

  /** A click on Not now, OK or × on the note on screen. Folding the island, or a note timing out, is not one. */
  noteDismissed(): void {
    this.notes.dismiss();
  }

  /** The island has collapsed after a dismissal: the held notes get their look now, never before the collapse. */
  noteCollapsed(): void {
    try {
      this.notes.retry();
    } catch {
      // The sidekick never breaks the island.
    }
  }

  /** The pointer is over the island while a note is up. */
  noteHovered(): void {
    this.notes.hovered();
  }

  /**
   * The app's state changed (the island's `State.notify`): held notes get another look, and a note folded away unseen is forgotten. The stuck rules are asked again only when
   * something they depend on changed (a card came or went, the rate limit started or ended). Cheap when nothing is held, shown or different.
   */
  stateChanged(): void {
    try {
      this.notes.stateChanged();
      if (ctxKey(this.context()) !== this.lastCtx) this.evaluate();
    } catch {
      // The sidekick never breaks the island: this runs inside State.notify, and what failed is not logged.
    }
  }

  /** The Sidekick settings changed in Settings (a switch, an Unmute): the gate looks again. */
  settingsChanged(): void {
    try {
      if (this.env.settings().on === false) this.notes.clear();
      this.notes.stateChanged();
      this.evaluate();
    } catch {
      // The sidekick never breaks the island: this runs inside State.notify, and what failed is not logged.
    }
  }

  /** What a nudge is about, to the moment: its kind, its session, and the session's last event and pending request. */
  private signature(n: Nudge): string {
    const s = this.ledger.snapshot.sessions.find((x) => x.key === n.key);
    return `${n.kind}|${n.key}|${s?.lastEventAt ?? 0}|${s?.pendingApprovalAt ?? 0}`;
  }

  /**
   * The user came back. Every nudge that fell due while they were away is dropped, not kept for later, and does not count as given (nothing was shown). Each one is set aside on a
   * copy of the ledger before the next is asked for, so a second quiet session that fell due too is dropped too.
   */
  private dropDueWhileAway(): void {
    try {
      const now = this.env.now();
      const ctx = { ...this.context(), away: false };
      let view = this.ruleView();
      for (let tries = view.sessions.length; tries > 0; tries--) {
        const r = stuckStep(view, now, ctx);
        if (r.nudge === null) break;
        this.droppedWhileAway.add(this.signature(r.nudge));
        view = markNudged(view, r.nudge.key, now);
      }
      if (this.droppedWhileAway.size > 64) this.droppedWhileAway.clear();
    } catch {
      // The sidekick never breaks the island.
    }
  }

  /**
   * The ledger the stuck rules read (the Mac's `ruleLedger`): a session whose request stepped back to its own app is held here, with no pending approval, so it has no waiting
   * deadline and no waiting nudge while its mark lives. The other sessions are read as they are. The ledger itself is not changed.
   */
  private ruleView(): Ledger {
    return { sessions: this.ledger.snapshot.sessions.map((s) => (s.state === "approval" && this.env.stepBackEnd?.(s.sessionId) != null ? { ...s, pendingApprovalAt: null } : s)) };
  }

  /** The earliest live stepped-back mark's end, when it is still to come: a lapse that has passed is not kept (the app was told once). */
  private nextLapse(now: number): number | null {
    const at = this.env.focusLapseAt?.() ?? null;
    return at !== null && at > now ? at : null;
  }

  private context(): StuckContext {
    return { ratelimit: this.env.world.ratelimit(), away: this.presence.away, cardShown: this.env.world.ownCard(), platform: this.env.platform, muted: mutedKinds(this.env.settings()) };
  }

  /**
   * Asks the stuck rules what, if anything, an agent should be nudged about now, offers it to the gate, and sets the clock to the next deadline (or stops it: with the switch off,
   * the user away, an agent rate-limited or nothing live there is no deadline). Called when a hook event comes, when the presence or the world changes, and when the clock fires.
   * A stepped-back mark's end is the one thing the clock wakes for even then: once per mark, and the app is told at it.
   */
  evaluate(): void {
    const now = this.env.now();
    // A stepped-back mark ran out since the last look: the app redraws its pill once, in the finally below, whatever the look did.
    const lapsed = this.focusLapseAt !== null && now >= this.focusLapseAt;
    if (lapsed) this.focusLapseAt = null;
    // The time this look sets the clock to. Undefined when the look threw before it got that far: the finally then keeps the clock's own deadline.
    let at: number | null | undefined;
    try {
      this.ledger.prune(now);
      const ctx = this.context();
      this.lastCtx = ctxKey(ctx);
      // The switch off, the user away or an agent rate-limited: nothing is said, and the only timer is a stepped-back mark's end. The rules say nothing then either.
      if (!this.env.settings().on || ctx.away || ctx.ratelimit) {
        this.focusLapseAt = this.nextLapse(now);
        at = this.focusLapseAt;
        return;
      }
      // One nudge at a time. A candidate the gate refuses, or that was dropped for the away period, is set aside on a copy of the ledger and the rules are asked again, so the
      // other quiet sessions are offered too. At most as many tries as there are sessions.
      let view = this.ruleView();
      for (let tries = view.sessions.length; tries > 0; tries--) {
        const n = stuckStep(view, now, ctx).nudge;
        if (n === null) break;
        if (!this.droppedWhileAway.has(this.signature(n))) {
          const text = nudgeText(n, this.ruleView(), now, ctx);
          const reason = this.notes.offer({ kind: n.kind, agentId: n.agentId, key: n.key, lines: [text], facts: [this.nudgeFacts(n, text)], awaySince: null });
          if (reason === "ok") break;
        }
        view = markNudged(view, n.key, now);
      }
      this.rewordWaiting(now, ctx);
      this.focusLapseAt = this.nextLapse(now);
      at = earlier(this.deadline(stuckStep(this.ruleView(), now, ctx).nextAt, now), this.focusLapseAt);
    } catch {
      // The sidekick never breaks the island.
    } finally {
      try {
        if (at === undefined) {
          // The look threw first: the lapse still to come is kept, and a deadline the clock already has stays (an earlier one wins; with none, nothing is cancelled).
          this.focusLapseAt = this.nextLapse(now);
          at = earlier(this.clock.due, this.focusLapseAt);
        }
        this.clock.arm(at ?? null);
      } catch {
        // The sidekick never breaks the island: a failed clock set leaves the clock as it was.
      }
      try {
        if (lapsed) this.env.focusLapsed?.();
      } catch {
        // A listener that fails must not throw out of the look (the clock is already set).
      }
    }
  }

  /** The facts a nudge's words were written from: the agent's name and the numbers in the words. Nothing of the work. */
  private nudgeFacts(nudge: Nudge, text: string): unknown {
    return { agent: agentName(nudge.agentId), agentId: nudge.agentId, kind: nudge.kind, counts: (text.match(/\d+/g) ?? []).map(Number) };
  }

  /** The earliest deadline: the rules' own, and the moment the app gives up on a request a waiting nudge is on screen for (its words then change in place). */
  private deadline(nextAt: number | null, now: number): number | null {
    let at = nextAt;
    const v = this.notes.current;
    if (v !== null && v.kind === "stuck.waiting") {
      const s = this.ledger.snapshot.sessions.find((x) => x.key === v.key);
      const giveUp = s?.pendingApprovalAt == null ? null : s.pendingApprovalAt + STUCK.GIVE_UP_MS[this.env.platform];
      if (giveUp !== null && giveUp > now && (at === null || giveUp < at)) at = giveUp;
    }
    return at;
  }

  /** Once the app has given up on the request, the waiting nudge says the terminal has it. That is the same note with other words, not a second nudge. */
  private rewordWaiting(now: number, ctx: StuckContext): void {
    const v = this.notes.current;
    if (v === null || v.kind !== "stuck.waiting") return;
    const nudge: Nudge = { kind: "stuck.waiting", reasonId: "waiting", key: v.key, agentId: v.agentId };
    this.notes.reword(v.id, [nudgeText(nudge, this.ruleView(), now, ctx)]);
  }

  /** A nudge that waited for the gate is only shown if it is still true: the rules still choose its own session and kind, once the sessions before it are set aside. A recap always is. */
  private stillTrue(note: Note): boolean {
    if (note.kind === "recap") return true;
    const now = this.env.now();
    const ctx = { ...this.context(), away: false };
    let view = this.ruleView();
    for (let tries = view.sessions.length; tries > 0; tries--) {
      const n = stuckStep(view, now, ctx).nudge;
      if (n === null) return false;
      if (n.kind === note.kind && n.key === note.key) return true;
      view = markNudged(view, n.key, now);
    }
    return false;
  }

  private back(r: Return): void {
    for (const fn of this.onReturn) {
      try {
        fn(r);
      } catch {
        // One listener's failure is its own.
      }
    }
  }
}
