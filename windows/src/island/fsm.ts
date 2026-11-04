// Island open/close FSM — port of IslandStateMachine.swift.
// No DOM, no Tauri: it only reports transitions.

import { cleanTuckChoice, hideDelay, type TuckChoice } from "./tuckaway.ts";

export type FsmState = "hidden" | "petit" | "home" | "hello";

export class IslandStateMachine {
  state: FsmState = "hidden";

  onTransition: ((from: FsmState, to: FsmState) => void) | null = null;

  /** home → petit delay, seconds. */
  homeToPetitDelay = 15;
  /** Tuck the island away (Settings → General → Behavior): "never" keeps the compact island up; a time hides it once nothing is live and that time has passed since the last activity (tuckaway.ts). */
  private tuckChoice: TuckChoice = "never";
  get tuckAway(): TuckChoice {
    return this.tuckChoice;
  }
  set tuckAway(value: TuckChoice) {
    this.tuckChoice = cleanTuckChoice(value);
    if (this.state === "petit") this.scheduleTuck();
  }
  /** Whether an agent is live right now (`isLive`), set by the island when it changes (`setLive`). */
  live = false;
  /** The clock the tuck-away rule reads, in seconds. A test replaces it. */
  now: () => number = () => performance.now() / 1000;
  /** The last hook event or alert (`agentActivity`), in seconds on `now`. Starts when the FSM is made, so a fresh island is not due at once. */
  lastActivity: number = this.now();
  /** The pointer is over the island (`mouseEntered` and `mouseLeft`): the compact island is not hidden under it. */
  private pointerInside = false;
  /** hello → petit once the greeting animation ends (no hover). */
  greetAutoCollapseDelay = 0.6;
  /** hello → petit while the mouse hovers the greeting. */
  greetHoverCollapseDelay = 10;
  /** An alert waiting for an answer stays open, even when the mouse leaves. Releasing the pin re-arms the tuck-away timer, so a due compact island hides at once (the Mac's hold release). */
  private pinnedFlag = false;
  get pinned(): boolean {
    return this.pinnedFlag;
  }
  set pinned(value: boolean) {
    this.pinnedFlag = value;
    if (!value && this.state === "petit") this.scheduleTuck();
  }
  /** The shelf's drag-out and its send each hold the island with their own flag (as the Mac's shelfDragging and sharePickerSince): one ending never releases the other. */
  private shelfHolds = { drag: false, send: false };
  setShelfHold(kind: "drag" | "send", on: boolean): void {
    this.shelfHolds[kind] = on;
    if (!on && this.state === "petit") this.scheduleTuck();
  }
  /** The island is held: an alert pin, the shelf's drag-out or its send. Every hold check reads this. */
  get held(): boolean {
    return this.pinnedFlag || this.shelfHolds.drag || this.shelfHolds.send;
  }
  /** Hovering opens the island all the way instead of peeking (Settings → General → Open on hover, off by default), as IslandStateMachine.openOnHover on the Mac. */
  openOnHover = false;
  /** The pointer must stay over the island this long, seconds, before Open on hover opens it; leaving earlier cancels it. The usual hover peek is not delayed. */
  hoverDwell = 0.15;
  /** Grace period after the pointer leaves a hover-opened island, seconds. */
  hoverCloseDelay = 0.6;
  /** Open because of a hover, until the user clicks inside it. */
  get openedByHover(): boolean {
    return this.byHover;
  }
  private byHover = false;
  /** A native menu of the island is open (the pointer is on it, outside the island): nothing folds while it is up. */
  menuOpen = false;
  /** The pointer is over a wing of the compact island (island/wing.ts): a hover-only hold, so Open on hover never opens the island from a wing. The click, the love emote and the cat's wake are untouched. */
  pointerOnWing = false;

  private petitHide: number | null = null;
  private homeCollapse: number | null = null;
  private greetCollapse: number | null = null;
  private hoverOpen: number | null = null;

  // ── Inputs ──────────────────────────────────────────────────────────────────

  launch() {
    this.cancelTimers();
    this.transition("hello");
  }

  mouseEntered() {
    this.pointerInside = true;
    switch (this.state) {
      case "hidden":
        this.cancelTimers();
        this.transition("petit");
        break;
      case "petit":
        this.clear("petitHide");
        break;
      case "home":
        this.clear("homeCollapse");
        break;
      case "hello":
        this.scheduleGreetCollapse(this.greetHoverCollapseDelay);
        break;
    }
    this.hoverResume();
  }

  /**
   * Open on hover: the island opens once the pointer has stayed `hoverDwell`. Not while an alert pins it, nor under an open native menu, nor from a wing. Also called when the pointer comes
   * off a wing into the middle while still over the island: there is no enter edge then, so the dwell is armed again here (it clears and re-arms its one one-shot timer).
   */
  hoverResume() {
    if (this.openOnHover && (this.state === "hidden" || this.state === "petit") && !this.held && !this.menuOpen && !this.pointerOnWing) this.scheduleHoverOpen();
  }

  private scheduleHoverOpen() {
    this.clear("hoverOpen");
    this.hoverOpen = window.setTimeout(() => {
      this.hoverOpen = null;
      if ((this.state !== "hidden" && this.state !== "petit") || this.held || this.menuOpen || this.pointerOnWing) return;
      this.cancelTimers();
      this.byHover = true;
      this.transition("home");
    }, this.hoverDwell * 1000);
  }

  mouseLeft() {
    this.pointerInside = false;
    this.clear("hoverOpen"); // leaving before the dwell is over cancels the open
    switch (this.state) {
      case "hidden":
        break;
      case "petit":
        this.scheduleTuck();
        break;
      case "home":
        this.scheduleHomeCollapse();
        break;
      case "hello":
        this.clear("greetCollapse");
        this.transition("petit");
        break;
    }
  }

  /** The menu opened or closed. Open: running fold timers are cancelled. Closed with the pointer outside the island: the fold timer starts now, as a mouseLeft would have. */
  menuHold(open: boolean, pointerInside: boolean) {
    this.menuOpen = open;
    if (open) {
      this.clear("petitHide");
      this.clear("homeCollapse");
    } else if (!pointerInside) this.mouseLeft();
  }

  click() {
    this.byHover = false;
    if (this.state !== "petit") return;
    this.cancelTimers();
    this.transition("home");
  }

  /** Greeting animation finished (T.end). Doesn't override a running hover timer. */
  greetComplete() {
    if (this.state !== "hello") return;
    if (this.greetCollapse == null) this.scheduleGreetCollapse(this.greetAutoCollapseDelay);
  }

  /** Non-alert work event: show compact from hidden. The transition arms the tuck-away timer. */
  reveal() {
    if (this.state !== "hidden") return;
    this.cancelTimers();
    this.transition("petit");
  }

  /** A hook event, an alert or a click on the island: the tuck-away count starts again from now, and a compact island that is up re-arms its one timer. */
  agentActivity() {
    this.lastActivity = this.now();
    if (this.state === "petit") this.scheduleTuck();
  }

  /** The live state changed (`isLive`). Only a change counts; a compact island that is up re-arms its timer for what is left. */
  setLive(value: boolean) {
    if (value === this.live) return;
    this.live = value;
    if (this.state === "petit") this.scheduleTuck();
  }

  /** A press on the island. Only the primary button counts as activity (the Mac's click is the left button); the others are no click for the tuck-away count. */
  userInteracted(primary = true) {
    if (primary) this.agentActivity(); // a click on the island is activity: the tuck-away count starts again
    if (!this.byHover) return;
    this.byHover = false;
    // The short countdown already running becomes the normal one.
    if (this.state === "home" && this.homeCollapse != null) this.scheduleHomeCollapse();
  }

  /** Alert or explicit request: open straight to expanded. */
  forceHome() {
    this.byHover = false;
    this.cancelTimers();
    this.transition("home");
  }

  /// Explicit close (OK button, Escape, an alert being answered).
  forcePetit() {
    this.byHover = false;
    this.cancelTimers();
    this.transition("petit");
  }

  forceHidden() {
    this.byHover = false;
    this.cancelTimers();
    this.transition("hidden");
  }

  // ── Timers ──────────────────────────────────────────────────────────────────

  /** The compact island's one timer (`petitHide`), armed for the rule's time. Only while it is up, the pointer is off it and no menu is open; nothing is armed for "never" or while something is live. */
  private scheduleTuck() {
    this.clear("petitHide");
    if (this.state !== "petit" || this.pointerInside || this.menuOpen || this.held) return;
    const delay = hideDelay(this.tuckChoice, this.lastActivity, this.now(), this.live);
    if (delay === null) return;
    this.petitHide = window.setTimeout(() => {
      this.petitHide = null;
      // Held (a menu or a pin): nothing here re-arms. The release (the menu closing, the pin's setter) arms it again.
      if (this.state !== "petit" || this.pointerInside || this.menuOpen || this.held) return;
      // Decided again now: a timer can fire a moment early, and then it is armed for what is left.
      if (hideDelay(this.tuckChoice, this.lastActivity, this.now(), this.live) === 0) this.transition("hidden");
      else this.scheduleTuck();
    }, delay * 1000);
  }

  private scheduleHomeCollapse() {
    this.clear("homeCollapse");
    if (this.held || this.menuOpen) return;
    const seconds = this.byHover ? this.hoverCloseDelay : this.homeToPetitDelay;
    this.homeCollapse = window.setTimeout(() => {
      this.homeCollapse = null;
      if (this.state === "home") {
        // A pin or a menu that arrived after the timer was armed holds a hover-opened island: it stays, as an ordinary open island.
        if (this.byHover && (this.held || this.menuOpen)) {
          this.byHover = false;
          return;
        }
        this.byHover = false;
        this.transition("petit");
      }
    }, seconds * 1000);
  }

  private scheduleGreetCollapse(delay: number) {
    this.clear("greetCollapse");
    this.greetCollapse = window.setTimeout(() => {
      this.greetCollapse = null;
      if (this.state === "hello") this.transition("petit");
    }, delay * 1000);
  }

  private clear(which: "petitHide" | "homeCollapse" | "greetCollapse" | "hoverOpen") {
    const id = this[which];
    if (id != null) window.clearTimeout(id);
    this[which] = null;
  }

  cancelTimers() {
    this.clear("petitHide");
    this.clear("homeCollapse");
    this.clear("greetCollapse");
    this.clear("hoverOpen");
  }

  private transition(next: FsmState) {
    if (next === this.state) return;
    const from = this.state;
    this.state = next;
    this.onTransition?.(from, next);
    if (next === "petit") this.scheduleTuck(); // the compact island is up: its tuck-away timer starts (nothing while the pointer is on it)
  }
}
