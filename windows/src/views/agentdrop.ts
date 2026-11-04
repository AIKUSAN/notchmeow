// The agents' cats while a file is dragged over the island (sub-project F1, spec "Drop on an agent's cat"). The drop view has no cats of its own, so a small strip is added to it, only
// while a file is on its way and only when there is an agent a path could be handed to: one chip per running agent that has a cat of its own in this display mode. Dropping on a chip copies the
// file's path; dropping anywhere else is the drop the island always had. Pure DOM, no timer of its own: the island shows it and hides it, and moves the highlight with the cursor it already has.

import { createMiniBot, pruneMiniBots } from "../cat/minibots";
import { State } from "../core/state";
import { agentName } from "../sidekick/core.ts";
import type { DropAgent, DropTarget } from "../sidekick/agentdrop.ts";
import { clear, h } from "./dom";

export class AgentDropStrip {
  readonly el = h("div", { id: "agent-drops" });
  private chips = new Map<string, HTMLElement>();

  /** Shows one chip per agent. With none, nothing is shown. */
  show(agents: readonly DropAgent[]): void {
    this.hide();
    const chips: HTMLElement[] = [];
    for (const a of agents) {
      const task = State.tasks.find((t) => t.id === a.agentId);
      if (!task) continue;
      const chip = h("div", { class: "ad-chip" }, createMiniBot(task, 20, a.cat), h("span", { text: agentName(a.agentId) }));
      this.chips.set(a.agentId, chip);
      chips.push(chip);
    }
    if (!chips.length) return;
    this.el.append(h("div", { class: "ad-hint", text: "Drop on a cat to copy the path" }), ...chips);
    this.el.classList.add("on");
  }

  hide(): void {
    this.el.classList.remove("on");
    clear(this.el);
    this.chips.clear();
    pruneMiniBots();
  }

  /** Where the chips are on the page now. */
  targets(): DropTarget[] {
    const out: DropTarget[] = [];
    for (const [agentId, chip] of this.chips) {
      const r = chip.getBoundingClientRect();
      out.push({ agentId, rect: { x: r.left, y: r.top, w: r.width, h: r.height } });
    }
    return out;
  }

  /** Lights the chip of the agent whose cat the pointer is over (null: none). */
  hover(agentId: string | null): void {
    for (const [id, chip] of this.chips) chip.classList.toggle("hot", id === agentId);
  }
}
