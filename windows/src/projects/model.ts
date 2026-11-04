// The Projects model (P-tauri, Task 3): the one place the island's Projects state lives. It holds the registry (memory only), each session's step,
// the pin, the last click, the peek, the section's open flag and the layout. Pure: no timer (the tick and the dwell are clock.ts, given their timer by the
// owner), no DOM, no network. A session's full cwd stays here and is read only by `cwdOf` (the jump); nothing it returns is shown, logged or stored.

import {
  bigCardOf, claudeOnly, emptyRegistry, islandLayout, projectEventFrom, projectsView, registryApply,
} from "./core.ts";
import type { Layout, ProjectRow, ProjectsView, Registry, SessionRow } from "./core.ts";
import { chevronShown, usesProjects } from "./cells.ts";
import { nextDelay as clockDelay } from "./clock.ts";
import { projectStep } from "./present.ts";
import type { LiveProject } from "./present.ts";

export interface ProjectsEnv { home: string; now: () => number }

export interface FrameInput {
  projectCats: unknown;
  mainCat: unknown;
  activePills: readonly string[];
  open: boolean;
  focusId: string | null;
  twoCats: boolean;
}

export interface ProjectsFrame {
  view: ProjectsView;
  big: ProjectRow | null;
  layout: Layout;
  usesProjects: boolean;
  chevron: boolean;
  panelShown: boolean;
  pinned: string | null;
  expanded: boolean;
  peeking: string | null;
}

/** The tag of Claude Code's events in the registry (projects-core.js CLAUDE_TAG). */
const CLAUDE_TAG = "claude";

export class ProjectsModel {
  private readonly home: string;
  private readonly now: () => number;
  private reg: Registry;
  private readonly steps = new Map<string, string>();
  private pinned: string | null = null;
  private clicked: string | null = null;
  private peeking: string | null = null;
  private expandedFlag = false;
  private current: Layout = "agents";

  constructor(env: Partial<ProjectsEnv> = {}) {
    this.home = env.home ?? "";
    this.now = env.now ?? (() => Date.now());
    this.reg = emptyRegistry(this.home);
  }

  /** One hook payload into the model. True when it made an event; a payload that is not one changes nothing and never throws. */
  hook(payload: unknown, waitIn?: string): boolean {
    // The feed never throws: a payload whose getter throws is a payload that made no event. One fixed sentence, never the payload or the error's text.
    try {
      const ev = projectEventFrom(payload, this.now(), waitIn);
      if (ev === null) return false;
      this.reg = registryApply(this.reg, ev);
      if (ev.agent === CLAUDE_TAG && ev.sessionId !== "") {
        if (ev.kind === "preTool") {
          const p = payload as Record<string, unknown>;
          const line = projectStep(p.tool_name, p.tool_input);
          if (line !== null) this.steps.set(ev.sessionId, line);
        } else if (ev.kind === "prompt") {
          this.steps.delete(ev.sessionId);
        }
      }
      for (const key of [...this.steps.keys()]) {
        if (!this.reg.sessions.some((s) => s.id === key)) this.steps.delete(key);
      }
      return true;
    } catch {
      console.error("[notchmeow] projects feed failed");
      return false;
    }
  }

  /** The registry's view now, with each session's step and nothing else (the companion's "Right now" reads it). */
  view(): ProjectsView {
    return projectsView(this.reg, this.now(), { steps: Object.fromEntries(this.steps) });
  }

  /** The frame the island draws now: the view, the big card (its pin and click are kept), the layout, the section and the peek. */
  frame(input: FrameInput): ProjectsFrame {
    const view = projectsView(this.reg, this.now(), { steps: Object.fromEntries(this.steps), projectCats: input.projectCats, mainCat: input.mainCat });
    this.keep(view);
    this.current = islandLayout(this.current, claudeOnly(input.activePills, this.reg.otherAgentSeen), input.open);
    const count = view.projects.length;
    const chevron = chevronShown(this.current, input.focusId, count, input.twoCats);
    const card = bigCardOf(view.projects, this.pinned, this.clicked);
    return {
      view,
      big: view.projects.find((p) => p.id === card.project) ?? null,
      layout: this.current,
      usesProjects: usesProjects(this.current, input.focusId, count, input.twoCats),
      chevron,
      panelShown: this.expandedFlag && chevron,
      pinned: this.pinned,
      expanded: this.expandedFlag,
      peeking: this.peeking,
    };
  }

  /** A click on a project's pill: that project is the big card (unless a pin holds). */
  select(projectId: string): void {
    this.clicked = projectId;
  }

  /** Pins a live project, or unpins it when it is the pinned one. One pin at a time; a project that is not live is not taken. */
  togglePin(projectId: string): void {
    const view = projectsView(this.reg, this.now());
    if (view.projects.some((p) => p.id === projectId)) this.pinned = this.pinned === projectId ? null : projectId;
    this.keep(view);
  }

  isPinned(projectId: string): boolean {
    return this.pinned === projectId;
  }

  /** The chevron: opens or closes the section under the panels. */
  toggleExpanded(): void {
    this.expandedFlag = !this.expandedFlag;
  }

  get expanded(): boolean {
    return this.expandedFlag;
  }

  /** The peek of a project over the left card, or none. A peek for a project that leaves is let go by `frame`. */
  setPeeking(id: string | null): void {
    this.peeking = id;
  }

  /** The full cwd of a session, for the jump only. Memory only. */
  cwdOf(sessionId: string): string | null {
    const s = this.reg.sessions.find((x) => x.id === sessionId);
    return s ? s.cwd : null;
  }

  /** The session of a project that was active last: the greatest lastAt, the first of a tie. */
  newestSession(p: ProjectRow): SessionRow | null {
    let best: SessionRow | null = null;
    for (const s of p.sessions) if (best === null || s.lastAt > best.lastAt) best = s;
    return best;
  }

  /** The projects a Settings list or a tray menu names: one per folder name, in pill order, with the first project's name. */
  liveProjects(view: ProjectsView): LiveProject[] {
    const seen = new Set<string>();
    const out: LiveProject[] = [];
    for (const p of view.projects) {
      if (seen.has(p.catKey)) continue;
      seen.add(p.catKey);
      out.push({ catKey: p.catKey, name: p.name });
    }
    return out;
  }

  /** The delay of the one tick from now. */
  nextDelay(): number {
    return clockDelay(this.reg, this.now());
  }

  get stepsSize(): number {
    return this.steps.size;
  }

  /** The pin and the click follow their projects, and a peek is let go when its project is gone. */
  private keep(view: ProjectsView): void {
    const card = bigCardOf(view.projects, this.pinned, this.clicked);
    this.pinned = card.pinned;
    this.clicked = card.clicked;
    if (this.peeking !== null && !view.projects.some((p) => p.id === this.peeking)) this.peeking = null;
  }
}
