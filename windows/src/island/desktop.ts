// The desktop cat, the island's half (sub-project H). The island's page is the brain: it knows the agents, the approvals and the settings, runs the trip (cat/desktoptrip.ts) and
// tells the desktop window's page, the body (desktop/body.ts), what to draw and where to fly; the body answers with clicks, moves and "flight done". Messages go through Rust
// (`desktop_relay`), which owns nothing of the rules. Everything the user can do ends here as one event of the contract's machine.

import { Bridge, onEvent } from "../core/bridge";
import { islandToSpot, spotToIsland } from "../core/notchspot";
import { defaultWorld } from "../cat/desktopview";
import type { DesktopWorld } from "../cat/desktopview";
import { State } from "../core/state";
import { BUSY } from "../cat/base";
import type { StateName } from "../cat/base";
import { bigCatCollar } from "../cat/collar";
import { shouldDance } from "../cat/dance";
import { cleanCatBlock, withDesktopSize, withOutfit } from "../cat/display";
import { DESKTOP_PHASE_INFO, desktopAlert, desktopSizeOf, spotOf } from "../cat/desktop";
import type { Spot } from "../cat/desktop";
import { DesktopTrip } from "../cat/desktoptrip";
import type { BodyLook, BodyMsg, BrainMsg } from "../cat/desktoptrip";

/** What the brain needs of the island. */
export interface DesktopHost {
  /** Opens the island at the notch, as a click on the notch does. */
  open(): void;
  /** A hover or a click wakes a sleeping cat (island/sleep.ts). */
  wake(kind: "hover" | "click"): void;
  /** The big cat's centre in the island window's px now. */
  notchLocal(): { x: number; y: number };
  /** The stored outfit changed (the desktop cat's Wardrobe menu): the island resolves it for today again and keeps Auto's one-shot only while it is `auto`. */
  outfitChanged(): void;
  /** A point of the island window (px) is over the notch: a desktop cat put down there goes home. The same test as for a cat carried out of the notch. */
  overNotch(x: number, y: number): boolean;
}

export class DesktopBrain {
  readonly trip: DesktopTrip;
  private world: DesktopWorld;
  private readonly host: DesktopHost;
  private last = "";
  private carrying = false;
  /** `start()` has fetched the screens: until then `world` is the default one and a settings change waits (`changedEarly`). */
  private started = false;
  private changedEarly = false;
  /** Where a cat put down on the notch was: the flight home starts there (the trip's own spot is only the one before the drag, and a move would clamp and save it). */
  private homeFrom: Spot | null = null;

  constructor(host: DesktopHost, world: DesktopWorld = defaultWorld()) {
    this.host = host;
    this.world = world;
    this.trip = new DesktopTrip({
      body: (m) => this.send(m),
      notchSpot: () => { const p = host.notchLocal(); return islandToSpot(this.world, p.x, p.y); },
      screens: () => this.world.screens,
      settings: () => State.settings.cat.desktop,
      save: (next) => {
        State.settings.cat = cleanCatBlock({ ...State.settings.cat, desktop: next });
        void Bridge.saveSettings(State.settings);
      },
      notchEmpty: (empty) => {
        if (State.desktopNotchEmpty === empty) return;
        State.desktopNotchEmpty = empty;
        State.notify();
      },
      // The tray's item reads "Bring the cat home" while the cat is out.
      phase: (p) => void Bridge.desktopMenuText(DESKTOP_PHASE_INFO[p].on),
    });
  }

  /** Looks at the screens once and listens to the desktop window. Call it after the settings are loaded. */
  async start(): Promise<void> {
    await this.refresh();
    await onEvent<BrainMsg>("desktop-msg", (m) => this.onMsg(m));
    State.subscribe(() => this.changed());
    this.started = true;
    if (this.changedEarly) this.settingsChanged();
  }

  /** The screens are asked for again (a monitor came or went). A failure keeps the world there was. */
  private async refresh(): Promise<void> {
    const w = await Bridge.desktopScreens();
    if (w && Array.isArray(w.screens)) this.world = w;
  }

  /** The tray's item: the cat takes the trip the item asks for. The world is looked at first: while the cat was home nothing watched the screens, and a spot or a notch place from before an undock is wrong. */
  async toggle(): Promise<void> {
    await this.refresh();
    this.trip.toggle();
  }

  /** The island's screen changed (Settings → screen, or a monitor came or went): the notch is somewhere else now, and a flight in the air follows it. */
  screenChanged(): void { void this.refresh().then(() => this.trip.notchMoved()); }

  get positioned(): boolean { return this.world.positioned; }

  private send(m: BodyMsg): void {
    // The body draws what it was last told: the first `show` or `fly` must come after a look.
    if (m.k === "show" || m.k === "fly") this.sendLook(true);
    void Bridge.desktopRelay("desktop", this.homeFrom && m.k === "fly" && m.dir === "in" ? { ...m, from: this.homeFrom } : m);
  }

  /** What the desktop cat looks like: the big cat as the cast and the focused agent make it. */
  private look(): BodyLook {
    const cast = State.cast, pill = cast.big.pill ?? "", state = State.effectiveState as StateName;
    return {
      coat: cast.big.cat, state, collar: bigCatCollar(state, State.focusTask?.color), kittens: pill ? State.kittens[pill] ?? [] : [], pill,
      dancing: shouldDance(State.musicPlaying, state, "compact"), working: BUSY.has(state), asleep: State.asleep, size: desktopSizeOf(State.settings.cat.desktop.size), now: performance.now(),
      outfit: State.outfit, outfitChoice: State.settings.cat.outfit,
    };
  }

  /** Tells the body how the cat looks; only a change is sent (the clock does not count), unless forced. */
  private sendLook(force = false): void {
    const look = this.look(), key = JSON.stringify({ ...look, now: 0 });
    if (!force && key === this.last) return;
    this.last = key;
    void Bridge.desktopRelay("desktop", { k: "look", look } satisfies BodyMsg);
  }

  /** Something in State changed: an approval or a question may have come or gone, and the cat may look different. */
  private changed(): void {
    this.trip.alert(desktopAlert({ approval: State.attentionNeeded, fileCatch: State.fileCatch(), transferOffer: State.linkOfferPending }));
    this.trip.notchMoved();
    if (DESKTOP_PHASE_INFO[this.trip.phase].drawn || this.carrying) this.sendLook();
  }

  /** The settings changed (the switch in Settings, a size): the trip takes the trip the stored "out" asks for, and the cat is looked at again. */
  settingsChanged(): void {
    if (!this.started) { this.changedEarly = true; return; }
    const act = () => { this.trip.sync(); if (DESKTOP_PHASE_INFO[this.trip.phase].drawn) this.sendLook(true); };
    // A trip is due: the world is looked at first (the cat may have been home while the screens changed), and the trip is asked for after.
    if (State.settings.cat.desktop.on !== DESKTOP_PHASE_INFO[this.trip.phase].on) void this.refresh().then(act);
    else act();
  }

  /** The greeting is over: a cat that was out flies back out. */
  afterGreeting(): void { this.trip.launch(); }

  private onMsg(m: BrainMsg): void {
    if (!m || typeof m !== "object") return;
    switch (m.k) {
      case "ready": this.sendLook(true); break;
      case "flightDone": this.trip.flightDone(); break;
      case "click": this.host.wake("click"); this.host.open(); break;
      case "doubleClick": this.trip.sendHome(); break;
      case "move": {
        // Put down on the notch (the contract's sendHome: "the cat dropped on the notch"): it flies home from where it was dropped. Anywhere else it is clamped and saved.
        const s = spotOf(m.spot), p = s && spotToIsland(this.world, s);
        if (s && p && this.host.overNotch(p.x, p.y)) {
          this.homeFrom = s;
          try { this.trip.sendHome(); } finally { this.homeFrom = null; }
        } else this.trip.move(m.spot);
        break;
      }
      case "wake": if (m.why === "hover" || m.why === "click") this.host.wake(m.why); break;
      case "screens": void this.refresh().then(() => this.trip.screensChanged()); break;
      case "outfit":
        // The desktop cat's Wardrobe submenu: the same choice as Settings → Wardrobe, stored once and applied at once.
        State.settings.cat = withOutfit(State.settings.cat, m.id);
        void Bridge.saveSettings(State.settings);
        this.host.outfitChanged();
        this.sendLook(true);
        break;
      case "menu":
        if (m.item === "open") this.host.open();
        else if (m.item === "home") this.trip.sendHome();
        else if (m.item === "small" || m.item === "medium" || m.item === "large") {
          State.settings.cat = withDesktopSize(State.settings.cat, m.item);
          void Bridge.saveSettings(State.settings);
          this.sendLook(true);
          // A bigger cat may now sit under the Dock or past an edge: the trip finds its spot again for the new size (spotFor holds it for that size).
          this.trip.screensChanged();
        }
        break;
    }
  }

  // ── Dragging the big cat out of the notch ───────────────────────────────────────────────────────────────────────────────────────────

  /** Only the cat at home can be taken out by hand (on GNOME too: the window comes up where the system puts it). */
  get canCarry(): boolean { return this.trip.phase === "home"; }

  /** The cat is out, or flying to or from the notch: an alert to the compact island's wings (island/wing.ts), as the Mac's `desktopPhase != .home`. */
  get awayFromHome(): boolean { return this.trip.phase !== "home"; }

  /** The drag began: the cat leaves the notch's spot and is carried by the pointer (the window follows it). */
  carryStart(): void {
    // The screens are looked at again as the cat leaves: the pointer's positions are turned into spots with the world, and a world from before an undock would put the cat off screen.
    void this.refresh();
    this.carrying = true;
    State.desktopNotchEmpty = true;
    State.notify();
    this.sendLook(true);
    this.send({ k: "carry", on: true });
  }

  /** The pointer is at (x, y) in the island window. */
  carry(x: number, y: number): void {
    const s = islandToSpot(this.world, x, y);
    void Bridge.desktopPlace(s.x, s.y);
  }

  /** The button was released at (x, y): the cat is put down on the desktop, or back in the notch when it was dropped on it (or the drop was refused). */
  carryEnd(x: number, y: number, onNotch: boolean): void {
    this.carrying = false;
    this.send({ k: "carry", on: false });
    const r = onNotch ? null : this.trip.dragOut(islandToSpot(this.world, x, y));
    if (r && r.act !== null) return;
    this.send({ k: "hide" });
    State.desktopNotchEmpty = false;
    State.notify();
  }
}

