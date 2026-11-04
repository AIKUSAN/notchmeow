// The upload canvas — port of UploadCanvasView.swift.
//
// While the sequence engine is active this canvas draws the whole island body:
// card, dashed drop frame, drop text, progress bar, the choose card, the cat and
// the file flying into its mouth. The island's own cat is hidden for the duration,
// because this canvas draws its own: it catches the file in four steps (open wide
// while the file hovers, snap wider on the drop, gulp with a squash, chew for 0.85 s
// with happy eyes), and coughs a refused file back up as a hairball. The file is
// drawn in front of the cat, hovering and flying, as in the prototype's catch.

import { BotEngine } from "../cat/engine";
import { FLIGHT_MS, flightAt } from "../cat/geometry";
import { drawCat } from "../cat/renderer";
import { State } from "../core/state";
import { USC, lerp, progressAt, type UploadFrame } from "./sequence";

const FONT = 'system-ui, "Segoe UI Variable Text", "Segoe UI", sans-serif';

/** Mirrors the reference `rr()`: a rounded rect, radius clamped to the box. */
function rr(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  const rad = Math.max(0, Math.min(r, w / 2, h / 2));
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, rad);
}

function text(
  ctx: CanvasRenderingContext2D,
  s: string,
  x: number,
  y: number,
  font: string,
  color: string,
  align: CanvasTextAlign = "left",
) {
  ctx.font = font;
  ctx.fillStyle = color;
  ctx.textAlign = align;
  // SwiftUI's .leading / .center / .trailing anchors are vertically centred.
  ctx.textBaseline = "middle";
  ctx.fillText(s, x, y);
}

export interface UploadCanvasActions {
  /** Primary button — hand the file to the chat. */
  ask(): void;
  /** Secondary button. */
  cancel(): void;
}

export class UploadCanvas {
  /** Wrapper holding the canvas and the two invisible choose buttons. */
  readonly el: HTMLElement;

  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D | null;
  private overlay: HTMLElement;
  private sizedFor = 0;

  /** The drop view's cat: the big cat's, from the cast (set every frame in `draw`). */
  readonly cat = new BotEngine();
  private lastWall = 0;

  constructor(actions: UploadCanvasActions) {
    this.canvas = document.createElement("canvas");
    this.canvas.id = "upload-canvas";

    // Invisible hit areas at the reference button positions. The labels are
    // painted on the canvas; these only catch the click.
    const mk = (x: number, w: number, onclick: () => void) => {
      const b = document.createElement("button");
      b.className = "upload-hit";
      b.style.left = `${x}px`;
      b.style.top = "113px";
      b.style.width = `${w}px`;
      b.style.height = "26px";
      b.addEventListener("click", onclick);
      return b;
    };
    this.overlay = document.createElement("div");
    this.overlay.id = "upload-overlay";
    this.overlay.append(mk(114, 168, actions.ask), mk(290, 120, actions.cancel));

    this.el = document.createElement("div");
    this.el.id = "upload-layer";
    this.el.append(this.canvas, this.overlay);

    this.ctx = this.canvas.getContext("2d");
  }

  /** A file is over the island (true) or left it (false): the cat opens wide, or closes its mouth again. */
  hover(on: boolean) { this.cat.fileHover(on); }

  /** The file was dropped: the cat snaps wider while the file flies in. */
  drop(name: string) { this.cat.fileDrop(name); }

  /** The app can't take this file: the cat coughs it back up as a hairball once it has swallowed it. */
  refuse() { this.cat.fileRefuse(); }

  /** `wallTime` in seconds drives the marching dashes, like the macOS timeline. */
  draw(f: UploadFrame, wallTime: number) {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    if (this.sizedFor !== dpr) {
      this.sizedFor = dpr;
      this.canvas.width = Math.round(USC.W * dpr);
      this.canvas.height = Math.round(USC.ISL_H * dpr);
      this.canvas.style.width = `${USC.W}px`;
      this.canvas.style.height = `${USC.ISL_H}px`;
    }
    const ctx = this.ctx;
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, USC.W, USC.ISL_H);

    // The cat moves on the wall clock, whatever the sequence says about the file.
    const dt = this.lastWall ? Math.min(0.05, Math.max(0, wallTime - this.lastWall)) : 0;
    this.lastWall = wallTime;
    this.cat.setCoat(State.cast.drop);
    this.cat.lookX = f.lookX;
    this.cat.lookY = f.lookY;
    this.cat.update(dt);

    this.drawScene(ctx, f, wallTime);

    // The buttons only exist once the choose card has faded in.
    this.overlay.style.display = f.chooseAlpha > 0.5 ? "block" : "none";
  }

  // ── Scene ─────────────────────────────────────────────────────────────────

  private drawScene(ctx: CanvasRenderingContext2D, f: UploadFrame, wallTime: number) {
    // Island background.
    ctx.fillStyle = "#000000";
    ctx.fillRect(0, 0, USC.W, USC.ISL_H);

    // Card.
    ctx.save();
    rr(ctx, USC.CARD_X, USC.CARD_Y, USC.CARD_W, USC.CARD_H, USC.CARD_R);
    ctx.clip();
    ctx.fillStyle = "#0D0E10";
    ctx.fillRect(USC.CARD_X, USC.CARD_Y, USC.CARD_W, USC.CARD_H);

    // Green glow, fanning up from the bottom edge of the card.
    if (f.greenWash > 0) {
      const gx = USC.CARD_X + USC.CARD_W / 2;
      const gy = USC.CARD_Y + USC.CARD_H;
      const g = ctx.createRadialGradient(gx, gy, 0, gx, gy, USC.CARD_H * 1.5);
      g.addColorStop(0, `rgba(40,212,130,${f.greenWash * 0.9})`);
      g.addColorStop(0.55, `rgba(40,212,130,${f.greenWash * 0.3})`);
      g.addColorStop(1, "rgba(40,212,130,0)");
      ctx.fillStyle = g;
      ctx.fillRect(USC.CARD_X, USC.CARD_Y, USC.CARD_W, USC.CARD_H);
    }
    ctx.restore();

    // Dashed border, marching left to right at ~20 pt/s.
    if (f.zoneAlpha > 0) {
      ctx.save();
      ctx.globalAlpha = f.zoneAlpha;
      ctx.strokeStyle = f.zoneOver ? "rgba(52,212,153,0.55)" : "rgba(255,255,255,0.14)";
      ctx.lineWidth = 1.5;
      ctx.setLineDash([6, 5]);
      ctx.lineDashOffset = -wallTime * 20;
      rr(ctx, USC.CARD_X + 0.75, USC.CARD_Y + 0.75, USC.CARD_W - 1.5, USC.CARD_H - 1.5, USC.CARD_R - 0.5);
      ctx.stroke();
      ctx.restore();
    }

    if (f.zoneAlpha > 0 && f.textAlpha > 0) this.drawDropText(ctx, f);
    if (f.barAlpha > 0 || f.barReveal > 0) this.drawProgressBar(ctx, f);
    if (f.chooseAlpha > 0) this.drawChoose(ctx, f);

    // The cat first, then the file: in front of the cat while it hovers and while it flies in, as in the prototype's catch.
    this.drawCat(ctx, f);
    this.drawFile(ctx, f);
  }

  // ── Drop zone text and chips ──────────────────────────────────────────────

  private drawDropText(ctx: CanvasRenderingContext2D, f: UploadFrame) {
    ctx.save();
    ctx.globalAlpha = f.textAlpha;
    text(ctx, "Drop your files here", USC.TEXT_X, USC.TEXT_Y - 4, `500 13px ${FONT}`, "#D5D7DB");

    let cx = USC.TEXT_X;
    for (const chip of ["PDF", "Images", "Code", "Docs"]) {
      // The macOS port measures chips the same rough way, so the row lines up.
      const w = chip.length * 6.5 + 16;
      ctx.fillStyle = "rgba(255,255,255,0.07)";
      rr(ctx, cx, USC.TEXT_Y + 9, w, 18, 9);
      ctx.fill();
      text(ctx, chip, cx + 8, USC.TEXT_Y + 18, `500 11px ${FONT}`, "#B9BDC4");
      cx += w + 6;
    }
    ctx.restore();
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  private drawProgressBar(ctx: CanvasRenderingContext2D, f: UploadFrame) {
    ctx.save();
    ctx.globalAlpha = Math.max(f.barAlpha, 0.001);

    const x0 = USC.BAR_X0;
    const x1 = USC.BAR_X1;
    const by = USC.BAR_Y;
    const barLen = (x1 - x0) * f.barReveal;

    const name = State.droppedFile?.name ?? "file";
    text(ctx, `Uploading ${name}`, x0, by - 30, `500 12.5px ${FONT}`, "#A9ADB5");

    if (f.check > 0) {
      ctx.save();
      ctx.translate(x1 - 8, by - 30);
      ctx.scale(f.check, f.check);
      ctx.beginPath();
      ctx.arc(0, 0, 8, 0, Math.PI * 2);
      ctx.fillStyle = "#34D399";
      ctx.fill();
      ctx.beginPath();
      ctx.moveTo(-3.6, 0.2);
      ctx.lineTo(-1, 2.8);
      ctx.lineTo(3.8, -2.6);
      ctx.strokeStyle = "#07130E";
      ctx.lineWidth = 2;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.stroke();
      ctx.restore();
    } else {
      text(ctx, `${Math.round(f.progress * 100)} %`, x1, by - 30, `500 12.5px ${FONT}`, "#A9ADB5", "right");
    }

    // Track.
    if (barLen > 0) {
      ctx.fillStyle = "rgba(255,255,255,0.08)";
      rr(ctx, x0, by - 3, barLen, 6, 3);
      ctx.fill();
    }

    // Fill.
    const fx = lerp(x0, x1, f.progress);
    if (fx > x0 + 1) {
      const flashGreen = `rgb(${Math.round(lerp(52, 110, f.flash))},${Math.round(
        lerp(211, 231, f.flash),
      )},${Math.round(lerp(153, 183, f.flash))})`;
      const g = ctx.createLinearGradient(x0, 0, fx, 0);
      g.addColorStop(0, "#1FA87A");
      g.addColorStop(1, flashGreen);
      ctx.fillStyle = g;
      rr(ctx, x0, by - 3, fx - x0, 6, 3);
      ctx.fill();
    }

    // Glow trail, its length driven by how fast the bar is moving.
    if (f.progress > 0.01 && f.progress < 1) {
      const v =
        (progressAt(f.t + 0.01, USC.T_PROG_START, f.progEnd) -
          progressAt(f.t, USC.T_PROG_START, f.progEnd)) / 0.01;
      const tl = Math.max(8, Math.min(34, 8 + v * 40));
      const g = ctx.createLinearGradient(fx - tl, 0, fx, 0);
      g.addColorStop(0, "rgba(52,212,153,0)");
      g.addColorStop(1, "rgba(110,231,183,0.6)");
      ctx.save();
      ctx.filter = "blur(3px)";
      ctx.fillStyle = g;
      rr(ctx, fx - tl, by - 4, tl, 8, 4);
      ctx.fill();
      ctx.restore();
    }
    ctx.restore();
  }

  // ── Choose card ───────────────────────────────────────────────────────────

  private drawChoose(ctx: CanvasRenderingContext2D, f: UploadFrame) {
    ctx.save();
    ctx.globalAlpha = f.chooseAlpha;
    ctx.translate(0, (1 - f.chooseAlpha) * 4);

    const name = State.droppedFile?.name ?? "file";
    text(ctx, `${name} is ready.`, 114, 80, `600 14px ${FONT}`, "#F5F6F8");
    const sub = State.dropReader ? `${State.dropReader} will read this.` : "What do you want to do with it?";
    text(ctx, sub, 114, 100, `400 12.5px ${FONT}`, "#9398A1");

    ctx.fillStyle = "#F5F6F8";
    rr(ctx, 114, 113, 168, 26, 13);
    ctx.fill();
    text(ctx, "Ask a question about it", 198, 126, `500 12.5px ${FONT}`, "#0B0C0E", "center");

    ctx.fillStyle = "rgba(255,255,255,0.09)";
    rr(ctx, 290, 113, 120, 26, 13);
    ctx.fill();
    text(ctx, "Cancel", 350, 126, `500 12.5px ${FONT}`, "#F1F2F4", "center");
    ctx.restore();
  }

  // ── The cat, and the file flying into its mouth ───────────────────────────

  private drawCat(ctx: CanvasRenderingContext2D, f: UploadFrame) {
    // The file has reached the mouth: gulp and chew, or, for a refused file, gag.
    if (!f.fileVisible) this.cat.fileArrived();
    // The big cat is on the desktop (or in the air): it flies in to catch the file, and until it has landed the island draws no cat of its own (never two cats). At home this is the shipping canvas.
    if (State.desktopNotchEmpty) return;
    // After the chew the cat shrinks into the progress ball and stretches with its speed: the sequence's own squash.
    const travelling = f.t >= USC.T_CHEW_END;
    drawCat(ctx, this.cat, f.x, f.y + f.hop, f.d, { tilt: f.tilt, squash: travelling ? [f.sx, f.sy] : undefined, badge: false });
  }

  private drawFile(ctx: CanvasRenderingContext2D, f: UploadFrame) {
    if (!f.fileVisible) return;
    const cx = f.cursorX, cy = f.cursorY + 14;
    const m = this.cat.mouthAt, b = this.cat.base;
    if (this.cat.fileStep !== "flying" || !m || !b) {
      ctx.save();
      ctx.globalAlpha = 0.92;
      drawDoc(ctx, cx, cy, 1, 1);
      ctx.restore();
      return;
    }
    // Dropped: the file arcs into the mouth over FLIGHT_MS and shrinks on the way.
    const k = Math.max(0, Math.min(1, (f.t - USC.T_DROP) / (FLIGHT_MS / 1000)));
    const w = flightAt({ x: cx, y: cy }, m, b.R, k);
    const sc = w.size / (0.62 * b.R);
    ctx.save();
    ctx.translate(w.x, w.y);
    ctx.rotate(w.rot);
    drawDoc(ctx, 0, 0, sc, sc);
    ctx.restore();
  }
}

// ── Document icon ───────────────────────────────────────────────────────────

/**
 * The generic sheet with a folded corner. macOS swaps in the real file icon from
 * NSWorkspace; Windows has no equivalent reachable from the webview, so this is
 * the shape in every case — it is the same fallback the Swift draws.
 */
function drawDoc(ctx: CanvasRenderingContext2D, cx: number, cy: number, wsc: number, hsc: number) {
  const w = 34 * wsc;
  const h = 42 * hsc;
  const x = cx - w / 2;
  const y = cy - h / 2;
  const fold = 8 * Math.min(wsc, hsc);

  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,0.45)";
  ctx.shadowBlur = 8;
  ctx.shadowOffsetY = 3;
  ctx.beginPath();
  ctx.moveTo(x + 2, y);
  ctx.lineTo(x + w - fold, y);
  ctx.lineTo(x + w, y + fold);
  ctx.lineTo(x + w, y + h - 2);
  ctx.quadraticCurveTo(x + w, y + h, x + w - 2, y + h);
  ctx.lineTo(x + 2, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - 2);
  ctx.lineTo(x, y + 2);
  ctx.quadraticCurveTo(x, y, x + 2, y);
  ctx.closePath();
  ctx.fillStyle = "#F4F4F6";
  ctx.fill();
  ctx.restore();

  ctx.beginPath();
  ctx.moveTo(x + w - fold, y);
  ctx.lineTo(x + w - fold, y + fold);
  ctx.lineTo(x + w, y + fold);
  ctx.closePath();
  ctx.fillStyle = "#D5D6DB";
  ctx.fill();

  ctx.fillStyle = "#3B82F5";
  rr(ctx, x + w * 0.18, y + h * 0.58, w * 0.64, h * 0.16, 2);
  ctx.fill();
}
