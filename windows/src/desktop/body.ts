// The desktop cat's window, the body (sub-project H): it draws the big cat (cat/desktopdraw.ts) as the island's page, the brain (island/desktop.ts), says it looks, runs the flight
// (cat/desktopflight.ts) and the drag, and answers with clicks, moves and "flight done". It runs the frame rate the rule gives (`desktopFps`) with one timer and nothing else: a cat that
// cannot be seen runs nothing. Pointer events only arrive over the cat's body, because Rust lets the mouse through everywhere else (src-tauri/src/desktop.rs).

import { CheckMenuItem, Menu, MenuItem, Submenu } from "@tauri-apps/api/menu";
import { Bridge, onEvent } from "../core/bridge";
import { buildWardrobeItems, tickWardrobe } from "../core/wardrobemenu";
import type { WardrobeItems } from "../core/wardrobemenu";
import type { Settings } from "../core/state";
import { defaultWorld } from "../cat/desktopview";
import type { DesktopWorld } from "../cat/desktopview";
import type { StateName } from "../cat/base";
import { cleanCatBlock } from "../cat/display";
import { DESKTOP_SIZE_IDS, desktopFps, desktopSizeOf } from "../cat/desktop";
import type { DesktopSizeId, Spot } from "../cat/desktop";
import { drawDesktopCat } from "../cat/desktopdraw";
import { DesktopFlight } from "../cat/desktopflight";
import { FrameGovernor } from "../cat/desktopgov";
import type { BodyLook, BodyMsg, BrainMsg } from "../cat/desktoptrip";
import { desktopWindowLayout, kittenSide } from "../cat/desktopview";
import type { DesktopWindowLayout } from "../cat/desktopview";
import { BotEngine, catCfg } from "../cat/engine";
import { cursorLook } from "../cat/geometry";
import { Gestures } from "../cat/gestures";
import type { Gesture } from "../cat/gestures";
import { KittenPool } from "../cat/kittendraw";
import { kittenView } from "../cat/kittens";
import { applyCatSettings } from "../cat/settings";

const SIZE_LABELS: Record<DesktopSizeId, string> = { small: "Small", medium: "Medium", large: "Large" };
/** The happy reaction to a click, and how long the cat is "in an emote" for the frame rate (ms): the longest emote of `cat-core.js`'s `EMOUTH` (love and proud), 1.8 s. */
const HAPPY_MS = 1800;
/** A kitten counts as motion for this long (ms) after any change to the kitten list, an arrival or a leave: `KITTEN_LEAVE_MS`, 0.6 s. */
const KITTEN_MOTION_MS = 600;
/** A hover tells the island's page at most this often (ms): it only needs to wake the cat. */
const WAKE_EVERY_MS = 2000;

export class DesktopBody {
  private readonly root: HTMLElement;
  private readonly cv = document.createElement("canvas");
  private readonly engine = new BotEngine();
  private readonly pool = new KittenPool();
  private world: DesktopWorld = defaultWorld();
  /** A look at the screens is on its way: one question at a time. */
  private refreshing = false;
  /** This system gives the page a cursor to ask for (Windows); without one (Linux) `askCursor` would only ever get null. */
  private cursorPoll = true;
  /** The right-click menu, built once and reused: a native menu's items are resources in Rust that nothing frees. */
  private menuParts: Promise<{ menu: Menu; sizes: CheckMenuItem[]; wardrobe: WardrobeItems }> | null = null;
  private look: BodyLook | null = null;
  /** The brain's clock minus ours: its kittens' times are in its clock. */
  private skew = 0;
  private lay: DesktopWindowLayout = desktopWindowLayout("medium", "shrimpy", 0, 1);
  private sentLayout = "";
  /** The head's centre on the desktop, in points. */
  private spot: Spot | null = null;
  private visible = false;
  private carrying = false;
  private dragging = false;
  private flight: DesktopFlight | null = null;
  private cursor: Spot | null = null;
  private cursorAsked = false;
  /** The system gave an app a cursor at least once (Windows, X11): without one (Wayland) the cat looks ahead unless the pointer is over it. */
  private globalCursor = false;
  private emoteUntil = 0;
  private kittenMotionUntil = 0;
  private kittenSig = "";
  /** The session is locked or the display is off (Rust's `away` message): the same as a hidden page for the frame rate. */
  private away = false;
  /** What Rust was last told by `desktopAwake`. */
  private awakeSent = false;
  /** When the cursor was last asked for (ms): the read is held to about 10 Hz. */
  private lastCursor = -1e9;
  private shownState = "";
  private lastWake = -1e9;
  private readonly gov: FrameGovernor;
  private readonly gest: Gestures;

  constructor(root: HTMLElement) {
    this.root = root;
    this.gov = new FrameGovernor(
      { now: () => performance.now(), raf: (cb) => requestAnimationFrame(cb), caf: (id) => cancelAnimationFrame(id), set: (fn, ms) => window.setTimeout(fn, ms), clear: (id) => window.clearTimeout(id) },
      (dt) => this.frame(dt),
    );
    this.gest = new Gestures({ set: (fn, ms) => window.setTimeout(fn, ms), clear: (id) => window.clearTimeout(id), emit: (g) => this.gesture(g) });
  }

  async start(): Promise<void> {
    this.root.append(this.cv);
    const boot = await Bridge.boot();
    if (boot) { this.applySettings(boot.settings); this.cursorPoll = boot.cursorPoll !== false; }
    this.world = (await Bridge.desktopScreens()) ?? this.world;
    void Bridge.desktopDoubleClick().then((ms) => { if (typeof ms === "number" && ms >= 200 && ms <= 900) this.gest.doubleMs = ms; });
    await onEvent<BodyMsg>("desktop-msg", (m) => this.handle(m));
    await onEvent<Settings>("settings-changed", (s) => this.applySettings(s));
    document.addEventListener("visibilitychange", () => this.rate());
    this.cv.addEventListener("pointerdown", (e) => { if (e.button === 0) { this.cv.setPointerCapture(e.pointerId); this.gest.press(e.clientX, e.clientY); } });
    this.cv.addEventListener("pointermove", (e) => { this.over(e); if (e.buttons & 1) this.gest.move(e.clientX, e.clientY); });
    this.cv.addEventListener("pointerup", (e) => { if (e.button === 0) this.gest.release(); });
    this.cv.addEventListener("pointercancel", () => this.gest.cancel());
    // The capture can end without a pointerup (the window lost it, a native menu or dialog took the pointer): without this the drag would stay set and, on Windows, the whole window would keep the mouse.
    this.cv.addEventListener("lostpointercapture", () => this.gest.cancel());
    this.cv.addEventListener("pointerleave", () => { if (!this.globalCursor) this.cursor = null; });
    this.cv.addEventListener("contextmenu", (e) => { e.preventDefault(); this.gest.cancel(); void this.menu(); });
    this.say({ k: "ready" });
  }

  private say(m: BrainMsg): void { void Bridge.desktopRelay("island", m); }

  private applySettings(s: Settings): void { applyCatSettings(catCfg, cleanCatBlock(s.cat)); }

  // ── From the brain ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  /** A message from the brain (public so the dev server can feed one by hand). */
  handle(m: BodyMsg): void {
    if (!m || typeof m !== "object") return;
    const now = performance.now();
    switch (m.k) {
      case "look":
        this.look = m.look;
        this.skew = m.look.now - now;
        this.relayout();
        break;
      case "carry":
        this.carrying = m.on;
        if (m.on) this.visible = true;
        if (m.on) void Bridge.desktopShow(true);
        break;
      case "emote": this.emote(m.name); break;
      case "away": this.away = m.on; break;
      case "show":
        this.refreshWorld();
        this.flight = null;
        this.present(m.spot);
        break;
      case "fly": {
        this.refreshWorld();
        // An alert or "Send home" can come while the cat is in the hand: it lets go, and the flight home starts where the cat is, not at the spot the brain last saved.
        if (this.dragging) { this.dragging = false; void Bridge.desktopDrag(false); this.gest.cancel(); }
        const from = m.dir === "in" && this.visible && this.spot ? this.spot : m.from;
        this.present(from);
        this.flight = new DesktopFlight(from, m.to, now + Math.max(0, m.delayMs ?? 0), m.dir);
        if (m.emote) this.emote(m.emote);
        break;
      }
      case "turn": this.flight?.turn(now); break;
      case "notchEnd": this.flight?.setNotch(m.spot); break;
      case "desktopEnd":
        this.refreshWorld();
        if (this.flight) this.flight.setDesktop(m.spot);
        else this.present(m.spot);
        break;
      case "hide":
        this.flight = null;
        this.visible = false;
        void Bridge.desktopShow(false);
        break;
    }
    this.rate();
    this.gov.poke();
  }

  /** Looks at the screens again: a monitor may have come or gone while the cat was home, and nothing watched. A failure keeps the world there was; the layout follows a world that changed. */
  private refreshWorld(): void {
    if (this.refreshing) return;
    this.refreshing = true;
    void Bridge.desktopScreens().then((w) => {
      if (w && Array.isArray(w.screens)) { this.world = w; this.relayout(); }
    }).catch(() => {}).finally(() => { this.refreshing = false; });
  }

  /** Shows the cat with its head at `spot`: the window is sized, put there and shown. */
  private present(spot: Spot): void {
    this.spot = spot;
    this.visible = true;
    this.relayout(true);
    void Bridge.desktopPlace(spot.x, spot.y);
    void Bridge.desktopShow(true);
  }

  private emote(name: string): void {
    this.engine.emote(name);
    this.emoteUntil = performance.now() + HAPPY_MS;
  }

  /** The window's size and what takes the mouse follow the cat's size, its coat and its kittens; Rust is told only when they change. */
  private relayout(force = false): void {
    const look = this.look;
    if (!look) return;
    const screen = this.spot ? this.world.screens.find((s) => this.spot!.x >= s.frame.x && this.spot!.x < s.frame.x + s.frame.w && this.spot!.y >= s.frame.y && this.spot!.y < s.frame.y + s.frame.h) : null;
    const side = screen && this.spot ? kittenSide(this.spot.x, screen.visible.x, screen.visible.w) : 1;
    this.lay = desktopWindowLayout(look.size, look.coat, look.kittens.length, side);
    const L = this.lay, key = JSON.stringify([L.w, L.h, L.headX, L.headY, L.shapes]);
    if (!force && key === this.sentLayout) return;
    this.sentLayout = key;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.cv.width = Math.round(L.w * dpr); this.cv.height = Math.round(L.h * dpr);
    this.cv.style.width = `${L.w}px`; this.cv.style.height = `${L.h}px`;
    void Bridge.desktopLayout(L.w, L.h, L.headX, L.headY, L.shapes.map((c) => ({ x: c.x, y: c.y, r: c.r })));
  }

  // ── The frame ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  private frame(dt: number): void {
    const now = performance.now(), look = this.look;
    if (this.flight) {
      const p = this.flight.at(now);
      this.spot = { x: p.x, y: p.y };
      if (this.world.positioned) void Bridge.desktopPlace(p.x, p.y);
      // Where the system places windows itself (GNOME) the window cannot fly: the flight is a hop inside the cat's own window.
      else this.cv.style.transform = `translateY(${-Math.sin(Math.PI * this.flight.progress(now)) * this.lay.D * 0.3}px)`;
      if (p.done) { this.flight = null; this.cv.style.transform = ""; this.say({ k: "flightDone" }); }
    }
    if (!look) return;
    this.askCursor();
    const kittens = kittenView(look.kittens, now + this.skew), sig = kittens.map((k) => `${k.id}${k.state === "leaving" ? "!" : ""}`).join();
    if (sig !== this.kittenSig) { this.kittenSig = sig; this.kittenMotionUntil = now + KITTEN_MOTION_MS; }
    if (this.shownState !== look.state) { this.shownState = look.state; this.engine.setState(look.state as StateName); }
    const c = this.cursor, at = this.spot, gaze = c && at && !look.asleep ? { x: cursorLook(c.x - at.x, 0).x, y: cursorLook(0, c.y - at.y).y } : { x: 0, y: 0 };
    const dpr = Math.min(2, window.devicePixelRatio || 1), ctx = this.cv.getContext("2d");
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, this.lay.w, this.lay.h);
    drawDesktopCat(ctx, this.engine, this.pool, this.lay, { coat: look.coat, collar: look.collar, kittens, lookX: gaze.x, lookY: gaze.y, dancing: look.dancing, pill: look.pill, outfit: look.outfit }, dt);
    this.rate();
  }

  /** Where the cursor is, in points, from Rust (Windows). One question at a time, and none while the cat is in the air, carried or away (a locked session or a display that is off): it looks at what it is doing. */
  private askCursor(): void {
    if (!this.cursorPoll || this.cursorAsked || this.flight || this.carrying || this.dragging || this.away || this.look?.asleep) return;
    const t = performance.now();
    if (t - this.lastCursor < 100) return;
    this.lastCursor = t;
    this.cursorAsked = true;
    void Bridge.desktopCursor().then((p) => { if (p) { this.cursor = p; this.globalCursor = true; } }).catch(() => {}).finally(() => { this.cursorAsked = false; });
  }

  /** The frame rate the cat needs now (cat/desktop.ts `desktopFps`): the governor keeps to it, and 0 stops every timer. */
  private rate(): void {
    const now = performance.now(), look = this.look, c = this.cursor, at = this.spot;
    this.gov.setRate(desktopFps({
      phase: this.flight ? "flyingOut" : this.visible || this.carrying ? "onDesktop" : "home", hidden: document.visibilityState === "hidden" || this.away, dragging: this.carrying || this.dragging,
      emote: now < this.emoteUntil, kittenMotion: now < this.kittenMotionUntil, dance: look?.dancing === true, asleep: look?.asleep === true, working: look?.working === true,
      ...(c && at ? { cursorDist: Math.hypot(c.x - at.x, c.y - at.y) } : {}),
    }));
    // Rust's light checks run only while the cat is awake: shown, awake, not away, page visible.
    const awake = this.visible && !this.away && look?.asleep !== true && document.visibilityState !== "hidden";
    if (awake !== this.awakeSent) { this.awakeSent = awake; void Bridge.desktopAwake(awake); }
  }

  // ── The pointer ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  /** Points per CSS px of this window. */
  private get k(): number { return (window.devicePixelRatio || 1) / (this.world.scale || 1); }

  /** The pointer is over the cat: where the system gives an app no cursor (Wayland), this is the only cursor it gets; and a hover wakes a sleeping cat. */
  private over(e: PointerEvent): void {
    if (this.spot) this.cursor = { x: this.spot.x + (e.clientX - this.lay.headX) * this.k, y: this.spot.y + (e.clientY - this.lay.headY) * this.k };
    const now = performance.now();
    if (now - this.lastWake > WAKE_EVERY_MS) { this.lastWake = now; this.say({ k: "wake", why: "hover" }); }
    this.rate();
  }

  private gesture(g: Gesture): void {
    switch (g.k) {
      case "click":
        this.emote("happy");
        this.say({ k: "wake", why: "click" });
        this.say({ k: "click" });
        break;
      case "double": this.say({ k: "doubleClick" }); break;
      case "dragStart":
        // A cat in the air is not taken by the hand: the press is ignored, and its moves with it (`dragging` stays false).
        if (this.flight) break;
        // Where the system moves windows itself (GNOME) it drags the window; the spot is still saved, and GNOME may not keep it.
        if (!this.world.positioned) { void Bridge.desktopNativeDrag(); this.gest.cancel(); break; }
        this.dragging = true;
        void Bridge.desktopDrag(true);
        break;
      case "drag":
        if (this.spot && this.dragging) {
          this.spot = { x: this.spot.x + g.dx * this.k, y: this.spot.y + g.dy * this.k };
          void Bridge.desktopPlace(this.spot.x, this.spot.y);
        }
        break;
      case "dragEnd":
        if (this.dragging) {
          this.dragging = false;
          void Bridge.desktopDrag(false);
          if (this.spot) this.say({ k: "move", spot: this.spot });
        }
        break;
    }
    this.rate();
  }

  /** The right-click menu: Open the notch, Send home, Size and Wardrobe. A native menu, so it needs no room in the window. */
  private async menu(): Promise<void> {
    this.menuParts ??= this.buildMenu();
    let parts: { menu: Menu; sizes: CheckMenuItem[]; wardrobe: WardrobeItems };
    try { parts = await this.menuParts; } catch { this.menuParts = null; return; }
    // Only the ticks move from one right-click to the next.
    const size = desktopSizeOf(this.look?.size);
    await Promise.all([...parts.sizes.map((c, i) => c.setChecked(DESKTOP_SIZE_IDS[i] === size)), tickWardrobe(parts.wardrobe, this.look?.outfitChoice)]);
    await parts.menu.popup();
  }

  private async buildMenu(): Promise<{ menu: Menu; sizes: CheckMenuItem[]; wardrobe: WardrobeItems }> {
    const sizes = await Promise.all(DESKTOP_SIZE_IDS.map((id) => CheckMenuItem.new({ id, text: SIZE_LABELS[id], checked: false, action: () => this.say({ k: "menu", item: id }) })));
    const open = await MenuItem.new({ id: "open", text: "Open the notch", action: () => this.say({ k: "menu", item: "open" }) });
    const home = await MenuItem.new({ id: "home", text: "Send home", action: () => this.say({ k: "menu", item: "home" }) });
    // Wardrobe (sub-project I): the 18 choices in the contract's order, with a tick on the stored one (core/wardrobemenu.ts).
    const wardrobe = await buildWardrobeItems((id) => this.say({ k: "outfit", id }));
    return { menu: await Menu.new({ items: [open, home, await Submenu.new({ text: "Size", items: sizes }), await Submenu.new({ text: "Wardrobe", items: wardrobe.items })] }), sizes, wardrobe };
  }
}
