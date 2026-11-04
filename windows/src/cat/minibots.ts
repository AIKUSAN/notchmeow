// Mini cats (pills + compact grid) — port of MiniBotCanvasView.
// Each canvas owns a BotEngine; the island's frame loop ticks every live one.

import { BotEngine } from "./engine.ts";
import { KittenPool, drawKittens } from "./kittendraw.ts";
import { State } from "../core/state.ts";
import type { BotEmoteName } from "../core/layout.ts";
import type { AgentTask } from "../core/state.ts";

interface MiniBot {
  canvas: HTMLCanvasElement;
  engine: BotEngine;
  cssSize: number;
  taskId: string;
}

const live = new Map<HTMLCanvasElement, MiniBot>();

/**
 * Creates a mini cat whose **body** is `bodySize` CSS pixels across, in the coat `cat` (the cast's, for its pill: cat/cast.ts `pills`).
 *
 * The engine draws the body at 60 % of its canvas, so the canvas is
 * `bodySize / 0.6` and is centred in a `bodySize` slot, overflowing it — the
 * same thing SwiftUI does with a `.frame(width: 22/0.6)` inside a
 * `.frame(width: 22)`. Sizing the canvas itself to `bodySize` would shrink the
 * whole drawing to 60 %, which is what used to happen.
 */
export function createMiniBot(task: AgentTask, bodySize: number, cat: string): HTMLElement {
  const slot = document.createElement("span");
  slot.className = "mini";
  slot.style.width = `${bodySize}px`;
  slot.style.height = `${bodySize}px`;

  const canvas = document.createElement("canvas");
  const engineSize = bodySize / 0.6;
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  canvas.width = Math.round(engineSize * dpr);
  canvas.height = Math.round(engineSize * dpr);
  canvas.style.width = `${engineSize}px`;
  canvas.style.height = `${engineSize}px`;
  slot.append(canvas);

  const engine = new BotEngine();
  engine.isMini = true;
  engine.setCoat(cat);
  engine.collarColor = task.color;
  engine.setState(State.shownState(task.state), true);

  live.set(canvas, { canvas, engine, cssSize: engineSize, taskId: task.id });
  return slot;
}

/** A one-off face on every live mini cat of a pill (the happy look after a path was copied for its agent). */
export function emoteMiniBots(taskId: string, name: BotEmoteName) {
  for (const mb of live.values()) if (mb.taskId === taskId) mb.engine.triggerEmote(name);
}

export function releaseMiniBot(canvas: HTMLCanvasElement) {
  live.delete(canvas);
}

/**
 * Changes the coat of a mini cat that createMiniBot made, in place: a kept project pill keeps its canvas and its engine (its state follows
 * syncMiniBotStates). Nothing when the slot holds no mini cat.
 */
export function setMiniBotCoat(slot: Element, cat: string) {
  const canvas = slot.querySelector("canvas");
  const mb = canvas ? live.get(canvas) : undefined;
  mb?.engine.setCoat(cat);
}

/** Drops every canvas no longer in the document (views are rebuilt wholesale). */
export function pruneMiniBots() {
  for (const [canvas] of live) {
    if (!canvas.isConnected) live.delete(canvas);
  }
}

export function syncMiniBotStates(tasks: AgentTask[]) {
  const coats = new Map(State.cast.pills.map((p) => [p.pill, p.cat]));
  for (const mb of live.values()) {
    const task = tasks.find((t) => t.id === mb.taskId);
    if (!task) continue;
    mb.engine.setState(State.shownState(task.state));
    mb.engine.collarColor = task.color;
    // The display mode, the Main cat or an agent's coat changed: the pill's cat follows the cast.
    const coat = coats.get(task.id);
    if (coat) mb.engine.setCoat(coat);
  }
}

export function tickMiniBots(dt: number) {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  for (const mb of live.values()) {
    const ctx = mb.canvas.getContext("2d");
    if (!ctx) continue;
    mb.engine.update(dt);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, mb.cssSize, mb.cssSize);
    mb.engine.draw(ctx, mb.cssSize, mb.cssSize);
  }
}

export const miniBotCount = () => live.size;

// ── Subagent kittens at the trailing end of an agent pill (spec §3): up to three small kittens and a "+N" ──────────────────────────────────────────────
/** A pill is 28 px high (`H`, the unit of the pill's kitten places); the strip is three heights wide, its right edge the pill's trailing edge. */
const PILL_H = 28;
const STRIP_W = 3 * PILL_H;
const strips = new Map<HTMLCanvasElement, { pill: string; n: number }>();
const stripPool = new KittenPool();

/** The canvas the pill's kittens are drawn on, to be appended to the pill. It draws nothing until the pill has a kitten. */
export function createKittenStrip(task: AgentTask): HTMLCanvasElement {
  const canvas = document.createElement("canvas");
  canvas.className = "pill-kits";
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  canvas.width = Math.round(STRIP_W * dpr);
  canvas.height = Math.round(PILL_H * dpr);
  canvas.style.width = `${STRIP_W}px`;
  canvas.style.height = `${PILL_H}px`;
  strips.set(canvas, { pill: task.id, n: 0 });
  return canvas;
}

/** One frame of every pill's kittens: the cast's coat for the pill is the parent's, and the label of the pill makes room for them. */
export function tickKittenStrips(dt: number) {
  const now = performance.now(), dpr = Math.min(2, window.devicePixelRatio || 1), coats = new Map(State.cast.pills.map((p) => [p.pill, p.cat]));
  for (const [canvas, s] of strips) {
    if (!canvas.isConnected) { strips.delete(canvas); continue; }
    const task = State.tasks.find((t) => t.id === s.pill), list = State.kittenView(s.pill, now), ctx = canvas.getContext("2d");
    if (!ctx || !task) continue;
    if (!list.length && s.n === 0) continue;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, STRIP_W, PILL_H);
    const slots = drawKittens(ctx, stripPool, { place: "pill", pill: s.pill, parentCat: coats.get(s.pill) ?? State.settings.cat.character, color: task.color, ox: STRIP_W, oy: PILL_H / 2, unit: PILL_H }, list, dt);
    s.n = list.length;
    // The pill's name makes room for what is drawn at its trailing end.
    const last = slots.shown[slots.shown.length - 1], room = (slots.moreAt ? -slots.moreAt.x + 0.35 : last ? -last.x + last.d / 2 + 0.2 : 0) * PILL_H;
    const pill = canvas.parentElement;
    if (pill) { pill.classList.toggle("has-kits", list.length > 0); pill.style.setProperty("--kit-w", `${list.length ? room : 0}px`); }
  }
  stripPool.endFrame();
}

/** How many pills have a strip: what the checks look at. */
export const kittenStripCount = () => strips.size;

/** The coat of every live mini cat, by pill ID: what the checks look at. */
export const miniBotCoats = (): Record<string, string> => Object.fromEntries([...live.values()].map((mb) => [mb.taskId, mb.engine.p.name]));
