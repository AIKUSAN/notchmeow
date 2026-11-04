// The desktop cat's trip as the island lives it (sub-project H, spec §1). `desktopStep` (desktop.ts, the contract) says which phase comes next and what to do; this runs it:
// it keeps the phase, turns every `act` into messages for the desktop window (the body) and calls for the rest (save the settings, empty the notch's big-cat spot). It does not draw
// and does not read a clock: everything it touches is in `TripEnv`, so the plain-Node checks (npm run check:cat) drive it with a fake one. The brain is the island's page; the body is
// the desktop window's page, which draws the cat and runs the flight (cat/desktopflight.ts) and answers with `BrainMsg`.

import { DESKTOP_PHASE_INFO, clampSpot, desktopStep, rememberSpot, spotFor, spotOf } from "./desktop.ts";
import type { DesktopEvent, DesktopPhase, DesktopSettings, DesktopSizeId, DesktopStep, Screen, Spot } from "./desktop.ts";
import type { Kitten } from "./kittens.ts";

/** How long the cat shows the surprised emote before it flies to the notch for an alert (ms). */
export const SURPRISE_MS = 450;

/** What the desktop cat looks like now, as the island's page (the brain) knows it: the body draws it. `now` is the brain's clock (`performance.now()`), the one the kittens' times are in. */
export interface BodyLook {
  coat: string; state: string; collar: string | null; kittens: Kitten[]; pill: string; dancing: boolean; working: boolean; asleep: boolean; size: DesktopSizeId; now: number;
  /** The outfit it wears (State.outfit, resolved: a drawn outfit ID or `none`). The kittens beside it never wear one. */
  outfit: string;
  /** The stored choice (one of the 18 IDs, `auto` included): the right-click menu's Wardrobe submenu ticks it. */
  outfitChoice: string;
}

/** What the brain tells the body. */
export type BodyMsg =
  /** How the cat looks (and its size): sent whenever it changes while the cat is on the desktop, and before the first `show` or `fly`. */
  | { k: "look"; look: BodyLook }
  /** The cat is carried by the pointer, out of the notch (`on`), or has been put down. */
  | { k: "carry"; on: boolean }
  /** Play an emote now (a click's happy). */
  | { k: "emote"; name: string }
  /** Show the cat at this spot, with no flight. */
  | { k: "show"; spot: Spot }
  /** Fly from `from` to `to`; `dir` says which end is the notch spot. A delay and an emote come first (the alert's surprise). */
  | { k: "fly"; from: Spot; to: Spot; dir: "out" | "in"; emote?: string; delayMs?: number }
  /** Reverse the flight in progress. */
  | { k: "turn" }
  /** The notch spot moved: the notch end of the flight follows. */
  | { k: "notchEnd"; spot: Spot }
  /** The desktop spot moved (the screens changed): put the cat there, or move the desktop end of the flight. */
  | { k: "desktopEnd"; spot: Spot }
  /** The session is locked or the display is off (`on`), or both are back: Rust says so from the platform's own notifications; the page draws nothing while away. */
  | { k: "away"; on: boolean }
  /** Stop drawing and hide the window. */
  | { k: "hide" };

/** What the body tells the brain. */
export type BrainMsg =
  | { k: "ready" }
  | { k: "flightDone" }
  | { k: "click" }
  | { k: "doubleClick" }
  | { k: "move"; spot: Spot }
  | { k: "dragOut"; spot: Spot }
  | { k: "menu"; item: "open" | "home" | "small" | "medium" | "large" }
  /** The Wardrobe submenu of the right-click menu: the user picked one of the 18 selection IDs. */
  | { k: "outfit"; id: string }
  | { k: "wake"; why: "hover" | "click" }
  | { k: "screens" };

export interface TripEnv {
  /** Sends a message to the desktop window. */
  body(msg: BodyMsg): void;
  /** The big cat's spot in the notch right now (the compact place, or the expanded one while the island is open for an alert), in points; null before the island knows. */
  notchSpot(): Spot | null;
  /** The connected screens, in points. */
  screens(): Screen[];
  /** The stored desktop settings, and a place to put new ones. */
  settings(): DesktopSettings;
  save(next: DesktopSettings): void;
  /** The big cat's spot in the notch is empty (true) while the cat is on the desktop or in the air. */
  notchEmpty(empty: boolean): void;
  /** The phase changed (the tray item's words follow it). */
  phase?(phase: DesktopPhase): void;
}

export class DesktopTrip {
  private _phase: DesktopPhase = "home";
  private spot: Spot | null = null;
  private alerting = false;
  /** The notch spot the flight in the air was last told about, so `notchMoved` sends only a change. */
  private notchKey = "";
  private readonly env: TripEnv;

  constructor(env: TripEnv) { this.env = env; }

  get phase(): DesktopPhase { return this._phase; }

  /** Runs one event through the machine and carries out what it says. An event that makes no sense in this phase changes nothing. */
  event(ev: DesktopEvent): DesktopStep {
    const r = desktopStep(this._phase, ev);
    if (r.act === null) return r;
    this._phase = r.state;
    // "On" is saved before the act: the act may save the spots too, and every save comes back to the island as a settings change (a command, `sync`). If the spots were saved first, the
    // echo of that save would still carry the old "on" and the cat would be sent home the moment it was placed. This way every echo agrees with the phase.
    const info = DESKTOP_PHASE_INFO[r.state], s = this.env.settings();
    if (s.on !== info.on) this.env.save({ ...s, on: info.on });
    this.perform(r.act, ev);
    this.env.notchEmpty(info.notchEmpty);
    this.env.phase?.(r.state);
    return r;
  }

  private notch(): Spot { return this.env.notchSpot() ?? this.spot ?? { x: 0, y: 0 }; }
  private keyOf = (p: Spot) => `${p.x},${p.y}`;
  /** Where the cat sits on the desktop now: the remembered spot for these screens, else the default one. */
  private desktopSpot(): Spot {
    const s = this.env.settings();
    return spotFor(s.spots, this.env.screens(), s.size) ?? this.spot ?? { x: 300, y: 300 };
  }
  /** Saves `spot`, held where the cat may sit, as this arrangement's spot, and returns it. With no screens nothing is kept and the spot stands as it came. */
  private remember(spot: Spot): Spot {
    const s = this.env.settings(), screens = this.env.screens(), clamped = clampSpot(spot, screens, s.size);
    if (!clamped) return spot;
    this.env.save({ ...s, spots: rememberSpot(s.spots, screens, clamped, s.size) });
    return clamped;
  }

  private perform(act: NonNullable<DesktopStep["act"]>, ev: DesktopEvent): void {
    const send = (m: Parameters<TripEnv["body"]>[0]) => this.env.body(m);
    switch (act) {
      case "place": case "move": {
        this.spot = this.remember(spotOf(ev.spot) as Spot);
        send({ k: "show", spot: this.spot });
        break;
      }
      case "flyOut": {
        const to = this.desktopSpot(), from = this.notch();
        this.spot = to;
        this.notchKey = this.keyOf(from);
        send({ k: "fly", from, to, dir: "out" });
        break;
      }
      case "flyHome": case "retract": {
        const from = this.spot ?? this.desktopSpot(), to = this.notch();
        this.notchKey = this.keyOf(to);
        send(act === "retract" ? { k: "fly", from, to, dir: "in", emote: "surprised", delayMs: SURPRISE_MS } : { k: "fly", from, to, dir: "in" });
        break;
      }
      case "turn":
        send({ k: "turn" });
        break;
      case "resettle":
        this.spot = this.desktopSpot();
        send({ k: "desktopEnd", spot: this.spot });
        break;
      case "dock": case "goHome":
        send({ k: "hide" });
        break;
      case "keep": case "land":
        break;
    }
  }

  // ── The events, one method each ───────────────────────────────────────────────────────────────────────────────────────────────────────

  /** The big cat was dropped on empty desktop at `spot`. */
  dragOut(spot: Spot) { return this.event({ type: "dragOut", spot }); }
  /** The desktop cat was released at `spot`. */
  move(spot: Spot) { return this.event({ type: "move", spot }); }
  toggle() { return this.event({ type: "toggle" }); }
  sendHome() { return this.event({ type: "sendHome" }); }
  flightDone() { return this.event({ type: "flightDone" }); }
  screensChanged() { return this.event({ type: "screensChanged" }); }
  /** The app started and the greeting is over: a cat that was out flies back out. */
  launch() { return this.settingsOn ? this.event({ type: "launch" }) : { state: this._phase, act: null }; }

  /** An approval or a question is pending (true) or both are clear (false). Only a change is an event. */
  alert(on: boolean): DesktopStep | null {
    if (on === this.alerting) return null;
    this.alerting = on;
    return this.event({ type: on ? "alertOn" : "alertOff" });
  }

  private get settingsOn(): boolean { return this.env.settings().on === true; }

  /** Settings changed (the switch in Settings, or the tray): the stored "out" says one thing and the phase another, so the cat takes the trip the switch asked for. */
  sync(): DesktopStep | null {
    return this.settingsOn === DESKTOP_PHASE_INFO[this._phase].on ? null : this.event({ type: "toggle" });
  }

  /** The notch spot moved (the island opened or shut): a flight in the air follows it. Only a change is sent. */
  notchMoved(): void {
    if (!DESKTOP_PHASE_INFO[this._phase].flight) return;
    const n = this.notch(), key = this.keyOf(n);
    if (key === this.notchKey) return;
    this.notchKey = key;
    this.env.body({ k: "notchEnd", spot: n });
  }
}
