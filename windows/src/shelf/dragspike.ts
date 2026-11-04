// The drag-out spike's trigger (sub-project G1, Task 1): a small green tab in the compact island that, pressed and moved 4 px, drags a test file out of the island through the native
// drag source (src-tauri/src/dragout.rs). It exists so a person can try the drag on a real Windows or Linux machine before the shelf depends on it: press the tab and drag it onto
// the desktop, a folder window, a mail window or a text editor. The tab says what happened. Dev server only: main.ts mounts it behind `import.meta.env.DEV`, so a release build does not
// contain it. Drag it by its own press, never by the shelf's: this is the check of the system, not of the shelf.

import { Bridge } from "../core/bridge";
import { PressDrag } from "../cat/pressdrag";

export function mountDragSpike(): void {
  const tab = document.createElement("div");
  tab.id = "nm-drag-spike";
  tab.textContent = "drag test file";
  tab.style.cssText = "position:fixed;top:4px;left:calc(50% - 64px);width:128px;height:24px;line-height:24px;text-align:center;z-index:99999;font:600 11px system-ui,sans-serif;color:#07130e;background:#34d399;border-radius:12px;cursor:grab;user-select:none";
  const press = new PressDrag();
  const say = (text: string) => { tab.textContent = text; window.setTimeout(() => (tab.textContent = "drag test file"), 4000); };
  tab.addEventListener("mousedown", (e) => {
    if (e.button !== 0) return;
    press.press(e.clientX, e.clientY);
    const move = (m: MouseEvent) => {
      if (press.move(m.clientX, m.clientY) !== "start") return;
      cleanup();
      press.cancel();
      Bridge.dragOutSpike().then((result) => say(`drag: ${result}`)).catch((err) => say(`drag failed: ${String(err).slice(0, 40)}`));
    };
    const up = () => { cleanup(); press.cancel(); };
    const cleanup = () => { window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up); };
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  });
  document.body.append(tab);
}
