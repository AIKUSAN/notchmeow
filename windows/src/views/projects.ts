// The Projects screen (sub-project P, Task 5): the island's "projects" view, the rows of a project's sessions, the project pills with their "+N" cell, the peek over a
// left card, and the keyed cells that keep a pill's element (its peek, its Pin target) while its project changes place. The rules are pure (projects/present.ts,
// cells.ts, clock.ts); this file is the DOM. It shows folder names, roles, states, host and step words only: never a session's full folder.

import { h, clear, svg } from "./dom";
import { ICONS } from "./icons";
import { State } from "../core/state";
import { openRoute } from "../core/openagent.ts";
import { createMiniBot, pruneMiniBots, setMiniBotCoat, syncMiniBotStates } from "../cat/minibots";
import type { ViewHost } from "./views";
import type { ProjectRow, SessionRow, SubagentRow } from "../projects/core.ts";
import type { ProjectsFrame } from "../projects/model.ts";
import {
  EMPTY_SCREEN, agoWord, bigStepLine, dotClass, hostWord, moreRowsWord, moreWord, projectTask, projectsWord, rowDetail, sessionsWord, subagentWord, waitingWord,
} from "../projects/present.ts";
import { cellKey, cut, gridCells, panelCells, peekLineCapacity, pillNameParts, type Cell } from "../projects/cells.ts";
import { PeekDwell, type OneShot } from "../projects/clock.ts";

/** What the island does for the Projects screen and its pills. Ids only: a session's folder is read by the island, never shown here. */
export interface ProjectActions {
  /** A pill's click: that project is the big card (unless a pin holds). */
  select(projectId: string): void;
  /** The big card's click and its ↗: the project's newest session's app. */
  jumpProject(projectId: string): void;
  /** A row's click: the approval card when that session owns it, else its app. */
  jumpSession(sessionId: string): void;
  /** A pill's right-click: Pin or Unpin. */
  menu(projectId: string): void;
  /** The chevron: opens or closes the section under the panels. */
  toggleExpanded(): void;
  /** A "+N" cell: the Projects screen. */
  openScreen(): void;
}

/** Where the views read the registry and write the peek to. The app's is `appProjectsSource`; a test gives its own. */
export interface ProjectsSource {
  frame(): ProjectsFrame;
  open(): boolean;
  peek(id: string | null): void;
}

export const appProjectsSource: ProjectsSource = {
  frame: () => State.projectsNow(),
  open: () => State.mode === "expanded",
  peek: (id) => {
    State.projects.setPeeking(id);
    State.notify();
  },
};

/** The peek's dwell timer: the island's one-shot timeouts. */
const TIMER: OneShot = { set: (fn, ms) => window.setTimeout(fn, ms), clear: (id) => window.clearTimeout(id) };

/** Every peek made, so the island can let go of all of them when it folds. */
const peeks = new Set<ProjectPeek>();

type Line = { row: SessionRow } | { sub: SubagentRow };

/** One session line: its state dot, its label, its note (amber) or step, and where it runs and how long ago. */
function rowLine(row: SessionRow, act: ProjectActions | null, open: boolean): HTMLElement {
  return h(
    "div",
    { class: row.dim ? "pj-row pj-dim" : "pj-row", onclick: act ? () => act.jumpSession(row.id) : undefined },
    h("span", { class: dotClass(row.state, open) }),
    h("span", { class: "pj-label", text: row.label }),
    h("span", { class: row.note === "" ? "pj-detail" : "pj-detail pj-note", text: rowDetail(row.note, row.step) }),
    h("span", { class: "pj-meta", text: `${hostWord(row.host)} · ${agoWord(row.agoMin)}` }),
  );
}

/** One subagent line: a 12 px cat of the project's coat, its state dot and its type. */
function subLine(p: ProjectRow, s: SubagentRow, open: boolean): HTMLElement {
  return h(
    "div",
    { class: "pj-sub" },
    createMiniBot(projectTask({ id: `${p.id}>${s.id}`, name: subagentWord(s.type), state: s.state }), 12, p.cat),
    h("span", { class: dotClass(s.state, open) }),
    h("span", { class: "pj-label", text: subagentWord(s.type) }),
  );
}

/**
 * A project's session lines, each session followed by its subagents. `act` null makes plain lines (the peek); `limit` cuts the lines to that many (the rule of
 * cells.ts `cut`) and ends them with "+N more". A line that is cut is never built, so no cat is made for it.
 */
export function sessionRows(p: ProjectRow, act: ProjectActions | null, open: boolean, limit?: number): HTMLElement {
  const lines: Line[] = [];
  for (const s of p.sessions) {
    lines.push({ row: s });
    for (const sub of s.subagents) lines.push({ sub });
  }
  const { shown, more } = limit === undefined ? { shown: lines.length, more: 0 } : cut(lines.length, limit);
  const box = h("div", { class: "pj-rows" });
  for (const line of lines.slice(0, shown)) box.append("row" in line ? rowLine(line.row, act, open) : subLine(p, line.sub, open));
  if (more > 0) box.append(h("div", { class: "pj-more", text: moreRowsWord(more) }));
  return box;
}

/** A project's section on the screen: its 20 px cat, its name, the waiting count in amber, and its session lines indented. */
function section(p: ProjectRow, act: ProjectActions, open: boolean): HTMLElement {
  return h(
    "div",
    { class: "pj-section" },
    h(
      "div",
      { class: "pj-head" },
      createMiniBot(projectTask(p), 20, p.cat),
      h("span", { class: "pj-name", text: p.name }),
      p.waiting > 0 ? h("span", { class: "pj-waiting", text: waitingWord(p.waiting) }) : null,
    ),
    h("div", { class: "pj-body" }, sessionRows(p, act, open)),
  );
}

/** A project's pill: its 22 px cat, its folder (and its detail, when the name has one), its state dot at the top right. Its click, right-click and hover are the island's. */
export function projectPill(p: ProjectRow, act: ProjectActions, peek: ProjectPeek | null, open: boolean): HTMLElement {
  const parts = pillNameParts(p.name);
  return h(
    "div",
    {
      class: p.dim ? "pill pj-pill pj-dim" : "pill pj-pill",
      title: p.name,
      onclick: () => act.select(p.id),
      oncontextmenu: (e: Event) => {
        e.preventDefault();
        act.menu(p.id);
      },
      onmouseenter: () => peek?.enter(p.id),
      onmouseleave: () => peek?.leave(),
    },
    createMiniBot(projectTask(p), 22, p.cat),
    h(
      "span",
      { class: "pj-name" },
      h("span", { class: "pj-folder", text: parts.folder }),
      parts.detail === null ? null : h("span", { class: "pj-detail", text: parts.detail }),
    ),
    h("span", { class: dotClass(p.state, open) }),
  );
}

/** The "+N" cell that stands for the projects the grid has no room for: a click opens the Projects screen. */
export function moreCell(count: number, act: ProjectActions): HTMLElement {
  return h("div", { class: "pill pj-pill pj-more-cell", onclick: () => act.openScreen() }, h("span", { class: "pj-name", text: moreWord(count) }));
}

/**
 * Lays the cells out in the host, in their order. Each cell is found by its key (cellKey), never by its slot: a kept element is refreshed by `refresh` (which
 * changes only what shows changed), a new key is built by `make` once, and an element whose key left is removed. Elements are moved only where they are out of place.
 * Returns how many elements it removed, so the caller prunes the mini cats only when something went.
 */
export function keyedCells(
  host: HTMLElement,
  cells: readonly Cell[],
  make: (c: Cell) => HTMLElement,
  kept: Map<string, HTMLElement>,
  refresh: (el: HTMLElement, c: Cell) => void,
): number {
  let removed = 0;
  const live = new Set<string>();
  let prev: Node | null = null;
  for (const c of cells) {
    const key = cellKey(c);
    live.add(key);
    let el = kept.get(cellKey(c));
    if (el === undefined) {
      el = make(c);
      kept.set(key, el);
    }
    refresh(el, c);
    const want: Node | null = prev === null ? host.firstChild : prev.nextSibling;
    if (want !== el) host.insertBefore(el, want);
    prev = el;
  }
  for (const [key, el] of kept) {
    if (live.has(key)) continue;
    el.remove();
    kept.delete(key);
    removed++;
  }
  return removed;
}

/**
 * The peek of a project: a card laid over the left card (its own box, pointer events off) with the project's name, its session count and its session lines
 * as many as the card holds. Shown after the dwell on a pill; it lets go when the pointer leaves, when the island closes, or when its project leaves.
 */
export class ProjectPeek {
  readonly el: HTMLElement;
  private readonly src: ProjectsSource;
  private readonly cardH: number;
  private readonly dwell: PeekDwell;

  constructor(src: ProjectsSource, card: HTMLElement, cardH: number) {
    this.src = src;
    this.cardH = cardH;
    this.el = h("div", { class: "pj-peek", hidden: true });
    card.append(this.el);
    this.dwell = new PeekDwell(TIMER, (id) => this.show(id), () => this.hide());
    peeks.add(this);
  }

  enter(id: string): void {
    this.dwell.enter(id);
  }

  leave(): void {
    this.dwell.leave();
  }

  /** Lets go, takes the element out and forgets the peek: its card is gone. */
  dispose(): void {
    this.leave();
    this.el.remove();
    peeks.delete(this);
  }

  /** Refills the shown peek from the frame, or lets go when the island is closed or its project is gone. */
  sync(): void {
    const id = this.dwell.shown;
    if (id === null) return;
    const p = this.project(id);
    if (!this.src.open() || p === null) return this.leave();
    this.fill(p);
  }

  private show(id: string): void {
    const p = this.project(id);
    if (!this.src.open() || p === null) return this.leave();
    this.src.peek(id);
    this.el.hidden = false;
    this.fill(p);
  }

  private hide(): void {
    this.el.hidden = true;
    clear(this.el);
    this.src.peek(null);
  }

  private fill(p: ProjectRow): void {
    clear(this.el);
    this.el.append(
      h("div", { class: "pj-peek-name", text: p.name }),
      h("div", { class: "pj-peek-count", text: sessionsWord(p.sessionCount) }),
      sessionRows(p, null, this.src.open(), peekLineCapacity(this.cardH)),
    );
    pruneMiniBots();
  }

  private project(id: string): ProjectRow | null {
    return this.src.frame().view.projects.find((p) => p.id === id) ?? null;
  }
}

/** Lets go of every peek: the island folds or hides. */
export function leaveAllPeeks(): void {
  for (const p of peeks) p.leave();
}

/** The Projects screen: one section per live project, its session lines under it, the empty words when no project runs. Redrawn only when what it shows changed. */
export function buildProjects(act: ProjectActions, src: ProjectsSource = appProjectsSource): ViewHost {
  const list = h("div", { class: "pj-list" });
  const empty = h("div", { class: "pj-empty", text: EMPTY_SCREEN });
  const el = h("div", { class: "view" }, h("div", { class: "card pj-card" }, h("div", { class: "pj-screen" }, list, empty)));
  let drawn = "";
  return {
    el,
    sync() {
      const open = src.open();
      const projects = src.frame().view.projects;
      const key = JSON.stringify([projects, open]);
      if (key === drawn) return;
      drawn = key;
      clear(list);
      for (const p of projects) list.append(section(p, act, open));
      list.style.display = projects.length === 0 ? "none" : "";
      empty.style.display = projects.length === 0 ? "" : "none";
      pruneMiniBots();
    },
  };
}

// ── The Claude-only card (Task 6): the big card, the project grid, the count capsule and the section ──────────────────────────────────────────────

/** Writes a text only when it differs: a kept element is not touched when nothing it shows changed. */
function setText(el: Element | null, text: string): void {
  if (el !== null && el.textContent !== text) el.textContent = text;
}

function setClass(el: Element, cls: string): void {
  if (el.className !== cls) el.className = cls;
}

function setFlag(el: Element, cls: string, on: boolean): void {
  if (el.classList.contains(cls) !== on) el.classList.toggle(cls, on);
}

function setHidden(el: HTMLElement, hidden: boolean): void {
  if (el.hidden !== hidden) el.hidden = hidden;
}

/**
 * A kept project pill follows its row in place: its class, its folder, its detail and its dot are written only when they changed. Its mini cat is made once
 * (by projectPill); only its state and coat are retargeted, and only when one of them changed.
 */
function refreshProjectPill(el: HTMLElement, p: ProjectRow, open: boolean): void {
  const parts = pillNameParts(p.name);
  setClass(el, p.dim ? "pill pj-pill pj-dim" : "pill pj-pill");
  if (el.title !== p.name) el.title = p.name;
  const shown = `${p.state}|${p.cat}`;
  if (el.dataset.shown !== shown) {
    el.dataset.shown = shown;
    const slot = el.querySelector(".mini");
    if (slot !== null) {
      syncMiniBotStates([projectTask(p)]);
      setMiniBotCoat(slot, p.cat);
    }
  }
  const name = el.querySelector(".pj-name");
  setText(name?.querySelector(".pj-folder") ?? null, parts.folder);
  const detail = el.querySelector<HTMLElement>(".pj-detail");
  if (parts.detail === null) detail?.remove();
  else if (detail === null) name?.append(h("span", { class: "pj-detail", text: parts.detail }));
  else setText(detail, parts.detail);
  const dot = el.querySelector<HTMLElement>(".pj-dot");
  if (dot !== null) setClass(dot, dotClass(p.state, open));
}

/**
 * The Claude-only card's body (the left card): the big project's state dot, its folder and its session count on one line, its detail on a line of its own, its
 * step (amber while a card waits), and its host and age. The card and its ↗ are one click: the project's newest session's app. Empty while the frame does not
 * use projects; its texts are written only when they changed.
 */
export function buildBigCard(src: ProjectsSource, act: ProjectActions): { el: HTMLElement; sync(): void } {
  let id = "";
  const dotEl = h("span");
  const name = h("span", { class: "pj-name" });
  const count = h("span", { class: "pj-count" });
  const detail = h("div", { class: "pj-big-detail" });
  const step = h("div", { class: "pj-big-step" });
  const meta = h("div", { class: "pj-big-meta" });
  const jumpBtn = h("button", { class: "icon-btn jump", title: "Open" }, svg(ICONS.arrowUpRight, 8));
  const el = h(
    "div",
    { class: "pj-big", onclick: () => act.jumpProject(id) },
    h("div", { class: "pj-big-top" }, dotEl, name, count),
    detail,
    step,
    meta,
    jumpBtn,
  );
  return {
    el,
    sync() {
      const f = src.frame();
      const big = f.big;
      if (!f.usesProjects || big === null) return;
      id = big.id;
      const parts = pillNameParts(big.name);
      setClass(dotEl, dotClass(big.state, src.open()));
      setText(name, parts.folder);
      setText(count, `· ${sessionsWord(big.sessionCount)}`);
      setHidden(detail, parts.detail === null);
      setText(detail, parts.detail ?? "");
      setClass(step, big.waiting > 0 ? "pj-big-step pj-note" : "pj-big-step");
      setText(step, bigStepLine(big));
      setText(meta, `${hostWord(big.host)} · ${agoWord(big.agoMin)}`);
      setFlag(el, "pj-dim", big.dim);
      const shown = openRoute("integration_claude", State.claudeApp, big.host === "claude-app") === "none" ? "none" : "";
      if (jumpBtn.style.display !== shown) jumpBtn.style.display = shown;
    },
  };
}

/** A project's tile in the section: its pill, and under it its sessions and its age. */
function tile(p: ProjectRow, act: ProjectActions, peek: ProjectPeek, open: boolean): HTMLElement {
  return h("div", { class: "pj-tile" }, projectPill(p, act, peek, open), h("div", { class: "pj-tile-meta" }));
}

/**
 * The Claude-only card's grid (the right card's `.pills`): the projects first, in the frame's order, then the other agents' pills while they fit, and "+N" for
 * the rest. Each cell is kept by its key; a pill whose badge changed is built again (its agent's own pill is not refreshed). Emptied, with its cats let go, while
 * the frame does not use projects.
 */
export function buildProjectGrid(
  src: ProjectsSource,
  act: ProjectActions,
  peek: ProjectPeek,
  otherPill: (id: string) => HTMLElement | null,
): { el: HTMLElement; sync(): void } {
  const el = h("div", { class: "pills" });
  const kept = new Map<string, HTMLElement>();
  const badges = new Map<string, string>();
  return {
    el,
    sync() {
      const f = src.frame();
      if (!f.usesProjects) {
        if (kept.size > 0) {
          clear(el);
          kept.clear();
          pruneMiniBots();
        }
        return;
      }
      const open = src.open();
      const byId = new Map(f.view.projects.map((p) => [p.id, p]));
      const tasks = new Map(State.pillRow.map(({ task }) => [task.id, task]));
      const cells = gridCells(f.view.projects.map((p) => p.id), [...tasks.keys()].filter((id) => id !== "integration_claude"));
      let gone = 0;
      for (const c of cells) {
        if (c.kind !== "pill") continue;
        const badge = tasks.get(c.id)?.pillBadge ?? "";
        if (badges.get(c.id) === badge) continue;
        badges.set(c.id, badge);
        const old = kept.get(cellKey(c));
        if (old !== undefined) {
          old.remove();
          kept.delete(cellKey(c));
          gone++;
        }
      }
      gone += keyedCells(
        el,
        cells,
        (c) => {
          if (c.kind === "more") return moreCell(c.count, act);
          if (c.kind === "pill") return otherPill(c.id) ?? h("span");
          return projectPill(byId.get(c.id)!, act, peek, open);
        },
        kept,
        (node, c) => {
          if (c.kind === "more") setText(node.querySelector(".pj-name"), moreWord(c.count));
          else if (c.kind === "project") refreshProjectPill(node, byId.get(c.id)!, open);
        },
      );
      if (gone > 0) pruneMiniBots();
    },
  };
}

/** The count capsule(s) and the chevron, for the Claude Code card's title row: a grey capsule with the live projects, an amber one with the waiting count when above 0, and the chevron that opens the section. */
export function buildTitleCap(act: ProjectActions): { el: HTMLElement; sync(f: ProjectsFrame): void } {
  const all = h("span", { class: "pj-capsule pj-all" });
  const wait = h("span", { class: "pj-capsule pj-wait" });
  // A stroked chevron: the path is an open line, which a fill draws as a dash at this size. 10 px fits the 16 px button, so the capsule does not grow.
  const chev = h("button", { class: "icon-btn pj-chev", onclick: () => act.toggleExpanded() }, svg(ICONS.chevronDown, 10, { stroke: 2 }));
  const el = h("span", { class: "pj-cap" }, all, wait, chev);
  return {
    el,
    sync(f) {
      const n = f.view.projects.length, m = f.view.waiting;
      setText(all, String(n));
      setHidden(wait, m === 0);
      setText(wait, String(m));
      setFlag(chev, "pj-up", f.expanded);
      const label = m > 0 ? `${projectsWord(n)}, ${waitingWord(m)}` : projectsWord(n);
      if (chev.getAttribute("aria-label") !== label) chev.setAttribute("aria-label", label);
    },
  };
}

/** The section under the two panels: the projects' count, the waiting count in amber, and one tile per project (the big card's outlined), or "+N". Shown only while the frame says so; cleared while it is not. */
export function buildClaudePanel(src: ProjectsSource, act: ProjectActions, peek: ProjectPeek): { el: HTMLElement; sync(f?: ProjectsFrame): void } {
  const n = h("span");
  const wait = h("span", { class: "pj-panel-wait" });
  const count = h("div", { class: "pj-panel-count" }, n, wait);
  const row = h("div", { class: "pj-panel-row" });
  const el = h("div", { class: "pj-panel" }, count, row);
  const kept = new Map<string, HTMLElement>();
  return {
    el,
    sync(f: ProjectsFrame = src.frame()) {
      if (!f.panelShown) {
        if (kept.size > 0) {
          // A tile's peek goes with its section: the tiles are cleared, so nothing may keep showing for one of them.
          peek.leave();
          clear(row);
          kept.clear();
          pruneMiniBots();
        }
        return;
      }
      const open = src.open();
      const list = f.view.projects;
      const byId = new Map(list.map((p) => [p.id, p]));
      const big = f.big?.id ?? null;
      setText(n, projectsWord(list.length));
      setText(wait, f.view.waiting > 0 ? ` · ${waitingWord(f.view.waiting)}` : "");
      const gone = keyedCells(
        row,
        panelCells(list.map((p) => p.id)),
        (c) => (c.kind === "more" ? moreCell(c.count, act) : tile(byId.get(c.id)!, act, peek, open)),
        kept,
        (node, c) => {
          if (c.kind === "more") {
            setText(node.querySelector(".pj-name"), moreWord(c.count));
            return;
          }
          const p = byId.get(c.id)!;
          refreshProjectPill(node.firstElementChild as HTMLElement, p, open);
          setText(node.querySelector(".pj-tile-meta"), `${sessionsWord(p.sessionCount)} · ${agoWord(p.agoMin)}`);
          setFlag(node, "pj-sel", p.id === big);
        },
      );
      if (gone > 0) pruneMiniBots();
    },
  };
}
