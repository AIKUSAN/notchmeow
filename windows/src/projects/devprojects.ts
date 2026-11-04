// The `?dev` page's "Projects" panel (P-tauri, Task 8): the Windows/Linux twin of the Mac's render-projects.sh and fake-projects-events.py. It draws the shipped Projects
// views (views/projects.ts) in five island frames, fed by a ProjectsModel of its own on a clock of its own: a scenario goes through the registry's hook path, the ages
// move the panel's clock, and the layout buttons pick the pills the island would see. Nothing here is the app's Projects state (State.projects is never read or written).
// Open http://127.0.0.1:1420/?dev with `npx vite` (no Tauri window needed). Only the dev server serves it: cat/dev.ts is loaded behind import.meta.env.DEV.
// It runs no loop and no timer of its own: each change redraws the frames once.

import { BotEngine } from "../cat/engine.ts";
import { State } from "../core/state.ts";
import { THEME } from "../theme.generated.ts";
import { badgeLabel, badgePlace, badgeShown } from "../shelf/badge.ts";
import { badgeTitle, hostWord, projectTask } from "./present.ts";
import { ProjectsModel } from "./model.ts";
import type { FrameInput, ProjectsFrame } from "./model.ts";
import type { ProjectRow } from "./core.ts";
import { PROJECT_SCENARIOS } from "./scenarios.ts";
import { buildBigCard, buildClaudePanel, buildProjectGrid, buildProjects, buildTitleCap, leaveAllPeeks, ProjectPeek } from "../views/projects.ts";
import type { ProjectActions, ProjectsSource } from "../views/projects.ts";

const B = THEME.brand;
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;
const HOME = "C:/dev/home";
const CLAUDE = "integration_claude";
const OTHER = "agent_codex";
const T0 = Date.now();
/** The big cat's body in the overview, in px (the expanded island's cat); the canvas is the body over 0.6, as the mini cats are. */
const BIG_BODY = 66;

function button(label: string, onclick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.style.cssText = BTN; b.textContent = label; b.onclick = onclick;
  return b;
}

function wrap(cls: string, ...children: Node[]): HTMLElement {
  const d = document.createElement("div");
  d.className = cls;
  d.append(...children);
  return d;
}

/** An island-sized black frame with its children in it. */
function stage(w: number, h: number, ...children: Node[]): HTMLElement {
  const s = wrap("", ...children);
  s.style.cssText = `position:relative;width:${w}px;max-width:100%;height:${h}px;background:#000;border-radius:0 0 22px 22px;overflow:hidden;margin:6px 0 4px`;
  return s;
}

function caption(text: string): HTMLParagraphElement {
  const p = document.createElement("p");
  p.style.cssText = `color:${B.dim};font-size:12px;margin:10px 0 0`;
  p.textContent = text;
  return p;
}

/** Writes a note only when it differs. */
function setNote(el: HTMLElement, text: string): void {
  if (el.textContent !== text) el.textContent = text;
}

/** The big cat of a project, still: its coat, its collar and its mood, drawn once per change of the panel. */
function bigCat(): { el: HTMLCanvasElement; paint(p: ProjectRow | null): void } {
  const D = BIG_BODY / 0.6;
  const dpr = Math.min(2, devicePixelRatio || 1);
  const el = document.createElement("canvas");
  el.width = Math.round(D * dpr);
  el.height = Math.round(D * dpr);
  el.style.cssText = `position:absolute;left:${54 - D / 2}px;top:${80 - D / 2}px;width:${D}px;height:${D}px;pointer-events:none`;
  const engine = new BotEngine();
  return {
    el,
    paint(p) {
      el.style.display = p === null ? "none" : "";
      if (p === null) return;
      const task = projectTask(p);
      engine.setCoat(p.cat);
      engine.collarColor = task.color;
      engine.setState(State.shownState(task.state), true);
      const c = el.getContext("2d")!;
      c.setTransform(dpr, 0, 0, dpr, 0, 0);
      c.clearRect(0, 0, D, D);
      engine.update(1 / 60);
      engine.draw(c, D, D);
    },
  };
}

export function mountProjectsDev(root: HTMLElement, before: Node | null): void {
  let offset = 0;
  const clock = () => T0 + offset;
  const newModel = () => new ProjectsModel({ home: HOME, now: clock });
  let model = newModel();
  let cur!: ProjectsFrame;
  let layoutWithAgents = false;
  let twoCats = false;
  const log: string[] = [];
  const paints: Array<() => void> = [];

  const src: ProjectsSource = {
    frame: () => cur,
    open: () => true,
    peek: (id) => model.setPeeking(id),
  };

  const findP = (id: string): ProjectRow | null => cur.view.projects.find((p) => p.id === id) ?? null;
  const said = (line: string) => { log.push(line); refresh(); };
  const jump = (host: string | undefined) => said(host === undefined ? "jump" : `jump ${hostWord(host)}`);
  const act: ProjectActions = {
    select: (id) => { const p = findP(id); if (p !== null) { model.select(id); said(`select ${p.name}`); } },
    jumpProject: (id) => jump(findP(id)?.host),
    jumpSession: (sid) => jump(cur.view.projects.flatMap((p) => p.sessions).find((s) => s.id === sid)?.host),
    menu: (id) => {
      const p = findP(id);
      if (p === null) return;
      const was = model.isPinned(id);
      model.togglePin(id);
      said(`${was ? "unpin" : "pin"} ${p.name}`);
    },
    toggleExpanded: () => { model.toggleExpanded(); said(`section ${model.expanded ? "open" : "closed"}`); },
    openScreen: () => said("open screen"),
  };

  // The frames. Each is the shipped view; the stage around it is the island's frame.
  const overview = (autoPeek: boolean) => {
    // The island's big cat fades while a peek shows on the left card: this overview's own source says when its peek is shown, and the stand-in cat follows.
    let peekOn = false;
    const cat = bigCat();
    const fadeCat = () => {
      const v = peekOn ? "0" : "1";
      if (cat.el.style.opacity !== v) cat.el.style.opacity = v;
    };
    const own: ProjectsSource = {
      frame: src.frame,
      open: src.open,
      peek: (id) => {
        model.setPeeking(id);
        peekOn = id !== null;
        fadeCat();
      },
    };
    const big = buildBigCard(own, act);
    const leftCard = wrap("card", big.el);
    const peek = new ProjectPeek(own, leftCard, 108);
    const grid = buildProjectGrid(own, act, peek, () => null);
    const rightCard = wrap("card", grid.el);
    const el = wrap("view overview on", wrap("left", leftCard), wrap("right", rightCard));
    return {
      el,
      cat: cat.el,
      paint() {
        big.sync();
        grid.sync();
        peek.sync();
        const show = cur.usesProjects;
        leftCard.style.display = show ? "" : "none";
        rightCard.style.display = show ? "" : "none";
        cat.paint(show ? cur.big : null);
        fadeCat();
        const first = cur.view.projects[0];
        if (autoPeek && show && first !== undefined) peek.enter(first.id);
      },
    };
  };

  const overviewA = overview(false);
  const overviewB = overview(true);
  paints.push(overviewA.paint, overviewB.paint);

  const agentsFrame = () => {
    const cap = buildTitleCap(act);
    const title = document.createElement("b");
    title.textContent = "Claude Code";
    const leftCard = wrap("card", wrap("card-body", wrap("int-head", title, cap.el)));
    const peek = new ProjectPeek(src, leftCard, 108);
    const panel = buildClaudePanel(src, act, peek);
    const rightCard = wrap("card", wrap("pills"));
    const el = wrap("view overview on", wrap("left", leftCard), wrap("right", rightCard), panel.el);
    return { el, paint: () => { el.classList.toggle("pj-open", cur.panelShown); cap.sync(cur); panel.sync(cur); } };
  };
  const agents = agentsFrame();
  paints.push(agents.paint);

  const screen = buildProjects(act, src);
  screen.el.classList.add("on");
  paints.push(() => screen.sync());

  // The compact strip: the waiting count at the badge's place, shown by the badge's own rule.
  const badge = document.createElement("button");
  badge.id = "projects-badge";
  const paintBadge = () => {
    const waiting = cur.view.waiting;
    const place = badgePlace(288, 32);
    badge.style.left = `${place.left}px`;
    badge.style.top = `${place.top}px`;
    badge.textContent = badgeLabel(waiting);
    badge.title = badgeTitle(waiting);
    badge.style.opacity = badgeShown("compact", waiting, false) ? "1" : "0";
  };
  paints.push(paintBadge);

  const note1 = caption(""), note2 = caption(""), note4 = caption("");
  const out = document.createElement("pre");
  out.id = "projects-dev-out";
  out.style.cssText = `color:${B.dim};font-size:12px;margin:0 0 10px;white-space:pre-wrap`;

  // The model's changes, through the same input the island's frame takes. The island's layout is sticky while it is open, so the closed pass first sets it from the pills.
  const input = (): FrameInput => ({
    projectCats: {}, mainCat: "shrimpy",
    activePills: layoutWithAgents ? [CLAUDE, OTHER] : [CLAUDE],
    open: true, focusId: CLAUDE, twoCats,
  });
  const layoutBtns = {
    only: button("Claude only", () => { layoutWithAgents = false; said("layout Claude only"); }),
    agents: button("With other agents", () => { layoutWithAgents = true; said("layout with other agents"); }),
    two: button("Two cats", () => { twoCats = !twoCats; said(`two cats ${twoCats ? "on" : "off"}`); }),
  };
  const mark = (b: HTMLButtonElement, on: boolean) => { b.style.borderColor = on ? B.accent : B.line; };

  function refresh(): void {
    const i = input();
    model.frame({ ...i, open: false });
    cur = model.frame(i);
    for (const paint of paints) paint();
    mark(layoutBtns.only, !layoutWithAgents);
    mark(layoutBtns.agents, layoutWithAgents);
    mark(layoutBtns.two, twoCats);
    setNote(note1, cur.usesProjects ? "" : "Not in use now: the layout is the agents' one, so the Claude-only overview is not drawn.");
    setNote(note2, cur.chevron ? (cur.panelShown ? "" : "The section is closed: press the chevron.") : "Not in use now: this is the agents' layout with the section open (With other agents).");
    setNote(note4, cur.usesProjects && cur.view.projects.length > 0 ? "" : "Not in use now: needs the Claude-only overview and a live project.");
    const pinned = cur.pinned === null ? "none" : findP(cur.pinned)?.name ?? "none";
    out.textContent = `Layout: ${cur.layout} · Projects: ${cur.view.projects.length} · Waiting: ${cur.view.waiting} · Section: ${cur.expanded ? "open" : "closed"} · Pinned: ${pinned}\nLog: ${log.slice(-4).join("  |  ") || "nothing yet"}`;
  }

  const run = (name: string) => {
    for (const step of PROJECT_SCENARIOS[name].steps) model.hook({ ...step.payload });
    said(`run ${name}`);
  };
  const age = (minutes: number, label: string) => {
    offset += minutes * 60_000;
    said(`age ${label}`);
  };
  const row = (label: string, ...buttons: HTMLButtonElement[]) => {
    const r = document.createElement("div");
    r.style.cssText = "display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px;align-items:center;font-size:12px";
    r.append(label, ...buttons);
    return r;
  };

  const box = document.createElement("section");
  box.id = "projects-dev";
  box.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
  box.innerHTML = `<h2 style="font-size:17px;font-weight:600;margin:0 0 2px">Projects</h2>
    <p style="color:${B.dim};margin:0 0 12px;font-size:13px">The Projects views fed by a registry in memory that follows the contract: pick a scenario, age it, switch the layout, pin. Nothing here is the app's own state.</p>`;
  box.append(
    row("Scenario:", ...Object.keys(PROJECT_SCENARIOS).map((name) => button(name, () => run(name)))),
    row("Age:", button("+10 min", () => age(10, "+10 min")), button("+30 min", () => age(30, "+30 min")), button("+2 h", () => age(120, "+2 h"))),
    row("Layout:", layoutBtns.only, layoutBtns.agents, layoutBtns.two),
    row("Pin:", button("Pin the first", () => { const first = cur.view.projects[0]; if (first !== undefined) act.menu(first.id); }),
      button("Clear", () => { leaveAllPeeks(); model = newModel(); log.length = 0; said("clear"); })),
    out,
    caption("1 · The Claude-only overview: the big card, the project grid and the big cat in the project's coat"), note1, stage(640, 160, overviewA.el, overviewA.cat),
    caption("2 · The agents layout with the section open: the count capsules, the chevron and the section under the card"), note2, stage(640, 252, agents.el),
    caption("3 · The Projects screen: one section per project, its session lines under it"), stage(640, 240, screen.el),
    caption("4 · A peek over the left card, for the first project (after the dwell)"), note4, stage(640, 160, overviewB.el, overviewB.cat),
    caption("5 · The compact strip: the waiting count, at the badge's place"), stage(288, 32, badge),
  );
  root.insertBefore(box, before);
  refresh();
}
