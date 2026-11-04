// What the island gives the Sidekick (sub-project F1): the clock, the system's name and the few questions only the app can answer. This is the one place the Sidekick's pure
// modules meet Tauri; they are given it, and import nothing of it themselves.

import { Bridge } from "../core/bridge";
import { State } from "../core/state";
import type { Island } from "../island/island";
import { cleanSidekickSettings } from "./core.ts";
import type { SidekickEnv } from "./controller.ts";
import { platformName } from "./platform.ts";
import { worldOf } from "./world.ts";
import { lapseMs, liveMarks, markForSession } from "../core/focusaware.ts";

/** Milliseconds added to the clock. Always 0 in the app; the dev server's `window.__nm.skew(ms)` moves it, so that a recap after minutes away can be looked at in seconds. */
export const Skew = { ms: 0 };

export function sidekickEnv(island: Island, home: string): SidekickEnv {
  return {
    now: () => Date.now() + Skew.ms,
    platform: platformName(),
    home,
    idleSeconds: async () => (await Bridge.sidekickIdleSeconds()) ?? null,
    settings: () => cleanSidekickSettings(State.settings.sidekick),
    saveSettings: (next) => {
      State.settings = { ...State.settings, sidekick: next };
      void Bridge.saveSettings(State.settings);
      State.notify();
    },
    world: worldOf(() => ({
      mode: State.mode, view: State.view, pendingApproval: State.pendingApproval, chatApprovals: State.chatApprovals, tasks: State.tasks, sidekickNoteId: State.sidekickNote?.id ?? null,
    })),
    // The island's own peek, the one a finished task uses: it opens on the note and folds again by itself, never pinned.
    present: (note) => {
      State.sidekickNote = note;
      island.alert("sidekick");
    },
    updated: (note) => {
      State.sidekickNote = note;
      State.notify();
    },
    oneshot: async (system, prompt) => (await Bridge.aiOneshot(system, prompt)) ?? null,
    hovering: () => island.pointerInside,
    // The stuck clock's one timer. Nothing else in the Sidekick sets one; `wait` only bounds an idle reading that does not answer, and is cleared when the reading settles.
    timer: { set: (fn, ms) => window.setTimeout(fn, ms), clear: (id) => window.clearTimeout(id) },
    wait: (ms, signal) => new Promise<void>((resolve) => {
      const id = window.setTimeout(resolve, ms);
      signal.addEventListener("abort", () => window.clearTimeout(id), { once: true });
    }),
    // Focus awareness: a stepped-back session's wait is held until its mark runs out, and the clock wakes then, once (the earliest live mark), and the app redraws.
    stepBackEnd: (id) => { const now = Date.now(); const m = markForSession(State.focusMarks, id, now); return m ? lapseMs(m.at, now, now + Skew.ms) : null; },
    focusLapseAt: () => { const now = Date.now(); const ends = liveMarks(State.focusMarks, now).map((m) => lapseMs(m.at, now, now + Skew.ms)); return ends.length ? Math.min(...ends) : null; },
    focusLapsed: () => State.notify(),
  };
}
