// Entry point of the desktop cat's window (sub-project H): a transparent page that draws the big cat when the island's page says so. The page is created hidden at launch
// (src-tauri/src/desktop.rs) and costs nothing while the cat is at home: no timer and no frame callback run until it is shown (cat/desktopgov.ts).

import { DesktopBody } from "./body";

// Not on the desktop cat: dropping files (spec §2). The window takes no file drop, and a file that lands on the page must never navigate it.
window.addEventListener("dragover", (e) => e.preventDefault());
window.addEventListener("drop", (e) => e.preventDefault());

const root = document.getElementById("desktop-root");
if (root) {
  const body = new DesktopBody(root);
  // Dev server only: `window.__body.handle({...})` feeds the page the same messages the island's page sends, so it can be looked at without the Tauri app.
  if (import.meta.env.DEV) (window as unknown as { __body: DesktopBody }).__body = body;
  void body.start();
}
