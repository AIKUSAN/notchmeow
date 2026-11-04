// Island views — DOM ports of IslandViewContent.swift. Paddings, font sizes,
// colours and wording are copied from the Swift views so both platforms read
// identically.

import { h, svg, clear, dot } from "./dom";
import { ICONS } from "./icons";
import { Ticker } from "./ticker";
import { State, type AgentTask } from "../core/state";
import { Bridge } from "../core/bridge";
import { agentLabel } from "../core/pills";
import { washRGBA, type BotEmoteName, type BotStateName, type IslandViewName, type Wash } from "../core/layout";
import { createKittenStrip, createMiniBot, pruneMiniBots } from "../cat/minibots";
import { buildPrompt } from "./chat";
import { islandLink } from "../companion/link.ts";
import { ClickGuard } from "./clickguard.ts";
import { buildChoose, buildUpload, buildUploading } from "./upload";
import { buildShelf, type ShelfActions } from "./shelf";
import { buildLink } from "./link";
import {
  appProjectsSource, buildBigCard, buildClaudePanel, buildProjectGrid, buildProjects, buildTitleCap, ProjectPeek, type ProjectActions,
} from "./projects";
import { renderIntegrationCard, type IntegrationCardHooks } from "./integrations";
import { badgeText } from "../sidekick/explain.ts";
import { finishedAction } from "../core/openagent.ts";
import { labelGivesWay } from "./titlefit.ts";
import { lineWaits, markForPill, noteText, showsNoteOverSecondLine } from "../core/focusaware.ts";

export interface ViewActions {
  setView(v: IslandViewName): void;
  collapse(): void;
  setFocus(id: string): void;
  openTerminal(): void;
  /** The Sidekick's note: a click on OK, Not now or × (one more dismissal of its kind), and "Open terminal" on a nudge (not a dismissal). */
  sidekickDismiss(): void;
  sidekickOpen(): void;
  /** The ↗ button: opens whatever the focused pill points at. */
  openTarget(): void;
  openUrl(url: string): void;
  decide(d: "allow" | "deny"): void;
  toggleSound(): void;
  setVolume(v: number): void;
  setAutoClose(seconds: number): void;
  openSettingsWindow(place?: string): void;
  blip(): void;
  /** A one-off face from the cat, e.g. a yawn while a local model wakes up. */
  emote(name: BotEmoteName): void;
  /** What the shelf view's tiles do (sub-project G1). */
  shelf: ShelfActions;
  /** What the Projects screen and its pills do (sub-project P). */
  projects: ProjectActions;
}

export interface ViewHost {
  el: HTMLElement;
  sync(): void;
  /** Called when the view becomes active, for views with a text field. */
  focus?(): void;
  /** The chat's model is read again (the Settings window changed a preference, so the cloud line may change). */
  refreshModel?(): Promise<void>;
  /** Called every frame while the view is on screen. */
  tick?(nowMs: number): void;
}

// ── Shared pieces ─────────────────────────────────────────────────────────────

function card(wash: Wash, ...children: (Node | string)[]): HTMLElement {
  const el = h("div", { class: wash ? "card wash" : "card" }, ...children);
  if (wash) el.style.setProperty("--wash", washRGBA(wash));
  return el;
}

function btn(
  label: string,
  kind: "primary" | "secondary",
  onClick: () => void,
  kbd?: string,
): HTMLElement {
  return h(
    "button",
    { class: `btn ${kind}`, onclick: onClick },
    h("span", { text: label }),
    kbd ? h("span", { class: "kbd", text: kbd }) : null,
  );
}

/** AgentWho — coloured dot + task name + grey label. */
function agentWho(task: AgentTask | null, label: string): HTMLElement {
  const row = h("div", { class: "who-row" });
  if (task) {
    row.append(dot(task.color, 8), h("span", { class: "n", text: task.name }));
  }
  row.append(h("span", { text: label }));
  return row;
}

function stack(padLeft: number, padRight: number, ...children: Node[]): HTMLElement {
  const el = h("div", { class: "stack" }, ...children);
  el.style.padding = `4px ${padRight}px 4px ${padLeft}px`;
  return el;
}

// ── Header ────────────────────────────────────────────────────────────────────

export function buildHeader(actions: ViewActions): ViewHost {
  const tabHome = h("button", { class: "tab", title: "Overview", onclick: () => go("overview") }, svg(ICONS.house, 13));
  // While the chat is in its own window, its tab brings that window forward (the island's chat view only says so).
  const tabChat = h("button", { class: "tab", title: "Ask", onclick: () => { go("prompt"); if (State.chatPoppedOut) void Bridge.showChatWindow(State.chatId); } }, svg(ICONS.bubble, 13));
  const tabDrop = h("button", { class: "tab", title: "Drop", onclick: () => go("upload") }, svg(ICONS.plus, 13));
  const tabProjects = h("button", { class: "tab", title: "Projects", onclick: () => go("projects") }, svg(ICONS.folder, 13));

  const gearBtn = h("button", { title: "Settings", onclick: () => go("settings") }, svg(ICONS.gear, 14));
  const soundBtn = h("button", { title: "Mute", onclick: () => actions.toggleSound() }, svg(ICONS.speakerOn, 14));

  function go(v: IslandViewName) {
    actions.blip();
    actions.setView(v);
  }

  const el = h(
    "div",
    { id: "header" },
    h("div", { class: "tabs" }, tabHome, tabChat, tabDrop, tabProjects),
    h("div", { class: "header-actions" }, gearBtn, soundBtn),
  );

  return {
    el,
    sync() {
      const v = State.view;
      tabHome.classList.toggle("on", v === "overview" || v === "empty");
      tabChat.classList.toggle("on", v === "prompt");
      tabDrop.classList.toggle("on", v === "upload");
      tabProjects.classList.toggle("on", v === "projects");
      gearBtn.classList.toggle("on", v === "settings");
      clear(gearBtn);
      gearBtn.append(svg(v === "settings" ? ICONS.gearFill : ICONS.gear, 14));
      clear(soundBtn);
      soundBtn.append(svg(State.settings.soundEnabled ? ICONS.speakerOn : ICONS.speakerOff, 14));
      el.style.opacity = v === "confused" ? "0" : "1";
    },
  };
}

// ── Overview ──────────────────────────────────────────────────────────────────

/** Two cats mode: what the ticker's second line says about cat 2's agent ("Codex · waiting for you"). */
const SECOND_LINE: Record<BotStateName, string> = {
  idle: "idle", working: "working", thinking: "thinking", searching: "searching", approval: "waiting for you", question: "has a question", error: "hit an error",
  finished: "finished", ratelimit: "rate limited", sleeping: "asleep", dizzy: "dizzy",
};

function buildOverview(actions: ViewActions): ViewHost {
  const ticker = new Ticker();
  const who = h("div", { class: "who" });
  const second = h("div", { class: "second" });
  const faNote = h("div", { class: "fa-note" });
  const tickerBody = h("div", { class: "card-body" }, who, ticker.el, faNote, second);
  const leftBody = h("div", { class: "left-body" });
  const jump = h(
    "button",
    { class: "icon-btn jump", title: "Open", onclick: () => actions.openTarget() },
    svg(ICONS.arrowUpRight, 8),
  );
  const left = card(null, leftBody, jump);
  const pills = h("div", { class: "pills" });
  const right = card(null, pills);

  // The Claude-only card (Projects): the big card and the project grid take the two cards while the frame uses projects; the section opens under them.
  const peek = new ProjectPeek(appProjectsSource, left, 108);
  const big = buildBigCard(appProjectsSource, actions.projects);
  const grid = buildProjectGrid(appProjectsSource, actions.projects, peek, (id) => {
    const row = State.pillRow.find(({ task }) => task.id === id);
    return row ? buildAgentPill(row.task, row.cat, actions) : null;
  });
  const cap = buildTitleCap(actions.projects);
  const panel = buildClaudePanel(appProjectsSource, actions.projects, peek);

  const el = h("div", { class: "view overview" },
    h("div", { class: "left" }, left),
    h("div", { class: "right" }, right),
    panel.el,
  );

  let pillIds = "";
  let detailOpen = false;
  let lastFocus: string | null = null;
  let mode: "ticker" | "card" | null = null;
  let cardKey = "";
  let projectsShown = false;

  const hooks: IntegrationCardHooks = {
    get detailOpen() {
      return detailOpen;
    },
    openDetail() {
      detailOpen = true;
      cardKey = "";
      State.notify();
    },
    closeDetail() {
      detailOpen = false;
      cardKey = "";
      State.notify();
    },
    openSettings: () => actions.openSettingsWindow("services"),
  };

  return {
    el,
    tick(nowMs: number) {
      if (mode === "ticker") ticker.tick(nowMs);
    },
    sync() {
      const frame = State.projectsNow();
      el.classList.toggle("pj-open", frame.panelShown);
      panel.sync(frame);
      peek.sync();
      cap.sync(frame);
      // Two cats (spec §2): the text moves right of the pair, and a second line names cat 2's agent.
      const two = State.cast.second;
      el.classList.toggle("two", two !== null);
      const other = two?.pill ? State.tasks.find((t) => t.id === two.pill) : undefined;
      second.textContent = two ? (other ? `${agentLabel(other.id)} · ${SECOND_LINE[State.shownState(other.state)]}` : "No other agent") : "";
      const mark = State.focusTask ? markForPill(State.focusMarks, State.focusTask.id, Date.now()) : null;
      const secondWaiting = Boolean(two?.pill && (State.pendingApproval?.pillId === two.pill || lineWaits(other ? State.shownState(other.state) : undefined)));
      const showNote = showsNoteOverSecondLine(mark !== null, secondWaiting);
      faNote.textContent = showNote && mark ? noteText(mark.host, mark.words) : "";
      faNote.style.display = showNote ? "block" : "none";
      second.style.display = showNote ? "none" : "";
      const task = State.focusTask;
      if (task?.id !== lastFocus) {
        lastFocus = task?.id ?? null;
        detailOpen = false;
        cardKey = "";
        mode = null;
      }

      // The Claude-only card: the big card and the grid take the two cards, and the shipped ↗ steps aside for the big card's own.
      if (frame.usesProjects) {
        if (!projectsShown) {
          projectsShown = true;
          mode = null;
          clear(leftBody);
          leftBody.append(big.el);
          pills.replaceWith(grid.el);
          pruneMiniBots();
        }
        jump.style.display = "none";
        big.sync();
        grid.sync();
        return;
      }
      if (projectsShown) {
        projectsShown = false;
        grid.el.replaceWith(pills);
        clear(leftBody);
        peek.leave();
        big.sync();
        grid.sync();
        mode = null;
        cardKey = "";
        pillIds = "";
      }

      // VS Code with a live Claude Code session keeps the ticker; every other
      // pill shows its own card, exactly like IntegrationCardView.
      const sessionActive =
        task?.id === "integration_claude" && (task.state !== "idle" || task.steps.length > 0);

      if (task && sessionActive) {
        if (mode !== "ticker") {
          clear(leftBody);
          leftBody.append(tickerBody);
          mode = "ticker";
          cardKey = "";
        }
        clear(who);
        const nameEl = h("span", { class: "name", text: task.name });
        const toolEl = h("span", { class: "tool", text: task.source === "claudeCode" ? "Claude Code" : "n8n" });
        who.append(dot(task.color, 7), nameEl, toolEl);
        if (frame.chevron) who.append(cap.el);
        if (task.steps.length > 1) {
          who.append(h("span", {
            class: "count",
            text: `${Math.min(task.stepIndex + 1, task.steps.length)}/${task.steps.length}`,
          }));
        }
        // The name gives way first: cut short with the label beside it, the label goes whole, never as a fragment (the Mac's ProjectsTitleFit rule).
        if (labelGivesWay(nameEl.scrollWidth, nameEl.clientWidth)) toolEl.remove();
        ticker.sync(task);
      } else if (task) {
        const info = State.integrations[task.id];
        const key = [
          task.id, detailOpen, frame.chevron, task.state, task.steps.join("|"),
          info?.loaded, info?.error, info?.configured,
          JSON.stringify(info?.data ?? {}),
        ].join("~");
        if (key !== cardKey) {
          cardKey = key;
          mode = "card";
          clear(leftBody);
          leftBody.append(renderIntegrationCard(task, hooks));
        }
        // The capsule sits in the Claude Code card's title row, in the chevron's frame only. When the name gives way, the kind goes and the label stays whole.
        const head = leftBody.querySelector<HTMLElement>(".int-head");
        const fit = frame.chevron && task.id === "integration_claude" && head !== null;
        if (head !== null) {
          head.classList.toggle("pj-fit", fit);
          if (fit && cap.el.parentNode !== head) head.append(cap.el);
          if (!fit) cap.el.remove();
          if (fit) {
            const name = head.querySelector("b") as HTMLElement;
            if (labelGivesWay(name.scrollWidth, name.clientWidth)) (head.querySelector(":scope > span:not(.pj-cap)") as HTMLElement | null)?.remove();
          }
        } else cap.el.remove();
      }

      jump.style.display = detailOpen ? "none" : "";

      const row = State.pillRow;
      const pillKey = row.map(({ task: t }) => `${t.id}:${t.pillBadge ?? ""}:${State.focusDot(t.id) ? 1 : 0}`).join("|");
      if (pillKey !== pillIds) {
        pillIds = pillKey;
        clear(pills);
        for (const { task, cat } of row) pills.append(buildAgentPill(task, cat, actions));
        pruneMiniBots();
      }
    },
  };
}

export function buildAgentPill(task: AgentTask, cat: string, actions: ViewActions): HTMLElement {
  const label = task.id === "integration_claude" ? "Claude Code" : task.name;
  const canvas = createMiniBot(task, 24, cat);
  const pill = h(
    "div",
    { class: "pill", onclick: () => actions.setFocus(task.id) },
    canvas,
    h("span", { class: "lbl", text: label }),
    createKittenStrip(task),
  );
  pill.style.borderColor = `${task.color}24`;
  pill.addEventListener("mouseenter", () => {
    pill.style.background = `${task.color}2e`;
    pill.style.borderColor = `${task.color}8c`;
    pill.style.boxShadow = `0 2px 10px ${task.color}59`;
    (pill.querySelector(".lbl") as HTMLElement).style.color = lighten(task.color, 0.3);
  });
  pill.addEventListener("mouseleave", () => {
    pill.style.background = "";
    pill.style.borderColor = `${task.color}24`;
    pill.style.boxShadow = "";
    (pill.querySelector(".lbl") as HTMLElement).style.color = "";
  });

  if (task.pillBadge) {
    const colors = { approval: "#F5A524", finished: "#22C55E", error: "#F4505E" } as const;
    const icons = { approval: ICONS.bang, finished: ICONS.check, error: ICONS.xmark } as const;
    const inner = h("i", { style: `background:${colors[task.pillBadge]}` }, svg(icons[task.pillBadge], 6, { stroke: task.pillBadge === "finished" ? 3 : 0 }));
    const badge = h("div", { class: "pill-badge" }, inner);
    badge.style.boxShadow = `0 0 4px ${colors[task.pillBadge]}99`;
    pill.append(badge);
  } else if (State.focusDot(task.id)) pill.append(h("div", { class: "fa-dot" }));
  return pill;
}

function lighten(hex: string, amount: number): string {
  const v = parseInt(hex.replace("#", ""), 16);
  const c = [(v >> 16) & 255, (v >> 8) & 255, v & 255].map((x) =>
    Math.min(255, Math.round(x + amount * 255)),
  );
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

// ── Empty ─────────────────────────────────────────────────────────────────────

function buildEmpty(actions: ViewActions): ViewHost {
  const body = h(
    "div",
    { class: "stack", style: "padding:0 18px 0 118px;flex-direction:row;align-items:center;gap:16px" },
    h(
      "div",
      { style: "display:flex;flex-direction:column;gap:5px" },
      h("div", { class: "title", text: "Nothing running right now." }),
      h("div", { class: "sub", text: "Drop a file or window, or ask me anything." }),
    ),
    h("div", { class: "grow" }),
    btn("Ask Claude", "primary", () => actions.setView("prompt")),
  );
  return { el: h("div", { class: "view" }, card(null, body)), sync() {} };
}

// ── Approval ──────────────────────────────────────────────────────────────────

function buildApproval(actions: ViewActions): ViewHost {
  const who = h("div");
  const code = h("div", { class: "code" });
  // The Sidekick's line (sub-project F1): one fixed grey sentence under the command, from the contract's `explain`.
  const why = h("div", { class: "sk-why" });
  const row = h("div", { class: "actions" });
  const el = h("div", { class: "view" }, card("amber", stack(116, 16, who, code, why, row)));
  let rowKey = "";
  // The card opens under a pointer that was busy with something else: a click meant for the window underneath must not land on Allow or Deny. Clicks in the first
  // 600 ms after a new request appears are ignored (the keys Y and N are not clicks).
  const guard = new ClickGuard();
  const guarded = (d: "allow" | "deny") => () => {
    if (guard.blocks(performance.now())) return;
    actions.decide(d);
  };
  return {
    el,
    sync() {
      guard.shown(State.pendingApproval?.requestId ?? null, performance.now());
      clear(who);
      const head = agentWho(State.focusTask, "needs permission");
      // The orange badge, at the trailing edge of the "who" row, on a high risk only.
      const badge = badgeText(State.pendingApproval?.risk);
      if (badge) head.append(h("span", { class: "sk-badge", text: badge }));
      who.append(head);
      why.textContent = State.pendingApproval?.line ?? "";
      why.style.display = State.pendingApproval?.line ? "" : "none";
      // The whole point of approving here rather than in the terminal: this line
      // is the command, the file path or the URL being authorised, not just the
      // name of the tool asking.
      code.textContent = State.pendingApproval?.command || State.pendingApproval?.tool || "…";
      // Two buttons, built once. Rebuilding them between a mouse-down and a
      // mouse-up would swallow the click, and there is nothing left to vary:
      // "Always" is gone until the remembered-rules list exists to back it.
      if (rowKey === "built") return;
      rowKey = "built";
      clear(row);
      row.append(
        btn("Deny", "secondary", guarded("deny"), "N"),
        btn("Allow", "primary", guarded("allow"), "Y"),
      );
    },
  };
}

// ── Question ──────────────────────────────────────────────────────────────────

function buildQuestion(): ViewHost {
  const who = h("div");
  const title = h("div", { class: "title" });
  const row = h("div", { class: "actions" });
  const el = h("div", { class: "view" }, card("cyan", stack(116, 16, who, title, row)));
  return {
    el,
    sync() {
      clear(who);
      who.append(agentWho(State.focusTask, "Claude Code is asking a question"));
      const task = State.focusTask;
      title.textContent = task?.steps.at(-1) ?? "Claude needs an answer.";
      clear(row);
      row.append(h("div", { class: "sub", text: "Answer in your terminal — NotchMeow can't reply for you yet." }));
    },
  };
}

// ── Error ─────────────────────────────────────────────────────────────────────

function buildError(actions: ViewActions): ViewHost {
  const who = h("div");
  const title = h("div", { class: "title", text: "Workflow stopped." });
  const detail = h("div", { class: "detail" });
  const row = h("div", { class: "actions" },
    btn("Retry", "primary", () => actions.setView(State.defaultView())),
    btn("Open in n8n", "secondary", () => actions.openUrl("")),
  );
  const el = h("div", { class: "view" }, card("red", stack(116, 16, who, title, detail, row)));
  return {
    el,
    sync() {
      const task = State.focusTask;
      clear(who);
      who.append(agentWho(task, task?.source === "n8n" ? "n8n" : "Claude Code"));
      title.textContent = task?.source === "n8n" ? "Workflow stopped." : "Session stopped on an error.";
      detail.textContent = task?.steps.at(-1) ?? "No detail available.";
    },
  };
}

// ── Finished ──────────────────────────────────────────────────────────────────

function buildFinished(actions: ViewActions): ViewHost {
  const who = h("div");
  const title = h("div", { class: "title" });
  const open = btn("Open terminal", "primary", () => actions.openTerminal());
  const row = h("div", { class: "actions" },
    open,
    btn("OK", "secondary", () => actions.collapse()),
  );
  const el = h("div", { class: "view" }, card("green", stack(116, 16, who, title, row)));
  return {
    el,
    sync() {
      clear(who);
      who.append(agentWho(State.focusTask, "Claude Code finished"));
      title.textContent = State.focusTask?.steps.at(-1) ?? "Session finished";
      // "Open terminal", or "Open Claude" for a session from the Claude desktop app; no button where there is no app to open (Linux). Core/openagent.ts.
      const act = finishedAction(State.focusTask?.id, State.claudeApp, State.claudeAppHost);
      open.style.display = act ? "" : "none";
      if (act && open.firstElementChild) open.firstElementChild.textContent = act.label;
    },
  };
}

// ── The Sidekick's note ───────────────────────────────────────────────────────

/** A recap ("Welcome back": what the agents did while you were away) or a nudge ("needs a look": one agent looks stuck). Built from the finished task's card. */
function buildSidekick(actions: ViewActions): ViewHost {
  const who = h("div");
  const lines = h("div", { class: "sk-lines" });
  const row = h("div", { class: "actions" });
  const close = h("button", { class: "icon-btn jump", title: "Dismiss", onclick: () => actions.sidekickDismiss() }, svg(ICONS.xmark, 8));
  const el = h("div", { class: "view" }, card("soft", stack(116, 28, who, lines, row)), close);
  let rowFor = -1;
  let wordsFor = "";
  return {
    el,
    sync() {
      const note = State.sidekickNote;
      if (!note) return;
      // The words can change under a note (a local model's nicer sentence, the waiting nudge at the give-up): the lines are rebuilt. The buttons are built once per note,
      // because rebuilding them between a mouse-down and a mouse-up would swallow the click.
      const words = note.lines.join("\n");
      if (words !== wordsFor || rowFor !== note.id) {
        wordsFor = words;
        // Lines rebuilt under the same note (a nicer sentence, the waiting nudge at the give-up) fade in.
        const fade = rowFor === note.id ? " sk-fresh" : "";
        clear(lines);
        note.lines.forEach((l, i) => lines.append(h("div", { class: (note.kind === "recap" ? "sub sk-line" : i === 0 ? "title" : "sub") + fade, text: l })));
      }
      if (rowFor === note.id) return;
      rowFor = note.id;
      clear(who);
      clear(row);
      const task = note.agentId ? State.tasks.find((t) => t.id === note.agentId) ?? null : null;
      who.append(agentWho(task, note.kind === "recap" ? "Welcome back" : "needs a look"));
      if (note.kind === "recap") row.append(btn("OK", "primary", () => actions.sidekickDismiss()));
      else {
        const act = finishedAction(note.agentId, State.claudeApp, State.claudeAppHost);
        row.append(btn("Not now", "secondary", () => actions.sidekickDismiss()));
        if (act) row.append(btn(act.label, "primary", () => actions.sidekickOpen()));
      }
    },
  };
}

// ── Confused ──────────────────────────────────────────────────────────────────

function buildConfused(): ViewHost {
  const body = h(
    "div",
    { class: "stack", style: "padding:0 18px 0 128px" },
    h("div", { class: "title", text: "Too many hits at once." }),
    h("div", { class: "sub", text: "Give me a sec — back to work in three seconds." }),
  );
  return { el: h("div", { class: "view" }, card("pink", body)), sync() {} };
}

// ── Note ──────────────────────────────────────────────────────────────────────

function buildNote(): ViewHost {
  const title = h("div", { class: "title" });
  const el = h("div", { class: "view" }, card(null, h("div", { class: "stack", style: "padding:0 18px 0 98px" }, title)));
  return {
    el,
    sync() {
      title.textContent = State.noteMessage ?? "";
    },
  };
}

// ── In-island settings ────────────────────────────────────────────────────────

function buildSettings(actions: ViewActions): ViewHost {
  const soundSwitch = h("button", { class: "switch", onclick: () => actions.toggleSound() });
  const volume = h("input", {
    type: "range", min: "0", max: "0.2", step: "0.005",
    oninput: (e: Event) => actions.setVolume(Number((e.target as HTMLInputElement).value)),
  }) as HTMLInputElement;
  const autoLabel = h("span", {});
  const segButtons = [10, 15, 30].map((s) =>
    h("button", { onclick: () => actions.setAutoClose(s) }, `${s}s`),
  );
  const claudeBadge = h("span", { class: "status-badge" });
  const apiBadge = h("span", { class: "status-badge" });

  const rows = h(
    "div",
    { class: "settings-rows" },
    h("div", { class: "settings-row" }, soundSwitch, h("span", { text: "Sound" }), volume),
    h(
      "div",
      { class: "settings-row" },
      svg(ICONS.timer, 12),
      autoLabel,
      h("div", { class: "seg" }, ...segButtons),
    ),
    h(
      "div",
      { class: "settings-row", style: "gap:14px" },
      claudeBadge,
      apiBadge,
      h("div", { class: "grow" }),
      h("button", {
        class: "link-btn",
        style: "color:#8e939c;font-size:11.5px",
        text: "Settings…",
        onclick: () => actions.openSettingsWindow(),
      }),
    ),
  );

  const el = h("div", { class: "view" },
    card(null, h("div", { class: "stack", style: "padding:14px 16px 14px 84px" }, rows)));

  return {
    el,
    sync() {
      const s = State.settings;
      soundSwitch.classList.toggle("on", s.soundEnabled);
      volume.value = String(s.soundVolume);
      volume.style.opacity = s.soundEnabled ? "1" : "0.4";
      autoLabel.textContent = `Auto-close · ${Math.round(s.autoCloseInterval)}s`;
      segButtons.forEach((b, i) => b.classList.toggle("on", s.autoCloseInterval === [10, 15, 30][i]));
      clear(claudeBadge);
      claudeBadge.append(
        dot(s.hooksInstalled ? "#22C55E" : "#F4505E", 6),
        h("span", { text: "Claude Code" }),
      );
      clear(apiBadge);
      apiBadge.append(dot("#F4505E", 6), h("span", { text: "API" }));
    },
  };
}

// ── Placeholders filled in later stages ───────────────────────────────────────

function buildPlaceholder(title: string, sub: string): ViewHost {
  const body = h(
    "div",
    { class: "stack", style: "padding:0 18px 0 118px" },
    h("div", { class: "title", text: title }),
    h("div", { class: "sub", text: sub }),
  );
  return { el: h("div", { class: "view" }, card(null, body)), sync() {} };
}

// ── Registry ──────────────────────────────────────────────────────────────────

export function buildViews(
  actions: ViewActions,
  onChatHeightChange: () => void,
): Map<IslandViewName, ViewHost> {
  const map = new Map<IslandViewName, ViewHost>();
  map.set("overview", buildOverview(actions));
  map.set("empty", buildEmpty(actions));
  map.set("approval", buildApproval(actions));
  map.set("question", buildQuestion());
  map.set("error", buildError(actions));
  map.set("finished", buildFinished(actions));
  map.set("confused", buildConfused());
  map.set("sidekick", buildSidekick(actions));
  map.set("note", buildNote());
  map.set("settings", buildSettings(actions));
  map.set("prompt", buildPrompt(actions, onChatHeightChange, islandLink()));
  map.set("upload", buildUpload());
  map.set("uploading", buildUploading());
  map.set("choose", buildChoose(actions));
  map.set("shelf", buildShelf(actions.shelf));
  map.set("link", buildLink());
  map.set("projects", buildProjects(actions.projects));
  // Not in the Windows v1: sending a file by email, window attach + web result.
  map.set("mail", buildPlaceholder("Sending by email isn't in this version.", ""));
  map.set("searching", buildPlaceholder("Claude is searching…", ""));
  map.set("result", buildPlaceholder("Result", ""));
  return map;
}
