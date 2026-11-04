// The Settings window's entry (Settings restyle, "The swap"): the six pages and the shell are in app.ts; this file starts them over the Tauri bridge.
// The dev server adds two routes, both behind import.meta.env.DEV: `settings.html?shot=<width>` (the picture frame) and `?sample=<state>` (the window on a stand-in backend).

import "./settings.css";
import "../link/link.css";
import { bridgeLinkBackend } from "../link/backend";
import { bridgeSettingsBackend } from "./backend.ts";
import { startSettingsApp } from "./app.ts";
import { migrate } from "./route.ts";

const root = document.getElementById("settings-root")!;
/** The window's store for the last page and tab. A store that cannot be opened (a blocked one) gives null, and the window still opens. */
function localStorageOrNull(): Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

async function main() {
  // The Settings window's dev samples (Task 5): `settings.html?shot=<width>` is the picture frame, `?sample=<state>` the window on a stand-in backend. Dev server only.
  const params = new URLSearchParams(location.search);
  const shot = import.meta.env.DEV ? params.get("shot") : null;
  if (shot) {
    const { mountShotFrame } = await import("./devpanel.ts");
    params.delete("shot");
    mountShotFrame(root, Number(shot), Number(params.get("h") ?? "2400"), `/settings.html?${params}`);
    return;
  }
  const sample = import.meta.env.DEV ? params.get("sample") : null;
  if (sample) {
    const theme = params.get("theme");
    if (theme === "light" || theme === "dark") document.documentElement.dataset.theme = theme;
    // A headless picture has no focus, and the cat loop draws only while the window can be seen: the dev sample says it is being seen (cat.ts).
    document.documentElement.dataset.shot = "1";
    const { devSettingsBackend, devTyped } = await import("./devseed.ts");
    const link = (await import("../link/devseed.ts")).devBackend(params.get("linkdev") ?? "on");
    const page = params.get("page");
    // font=wide (the layout check's --font wide): a wide stack and wider letter-spacing that stress the layout whichever face is drawn (it is not Segoe UI). Only the dev sample route takes it.
    if (params.get("font") === "wide") {
      document.documentElement.style.setProperty("--font", 'Verdana, "Trebuchet MS", Arial, sans-serif');
      document.documentElement.style.setProperty("letter-spacing", "0.04em");
    }
    // ?failsave=1 refuses the error sample's first save with the first switch focused (the note goes in its card); ?failsave=strip with nothing focused (the page strip).
    const refusal = sample === "error" ? params.get("failsave") : null;
    const failSave = refusal === "1" || refusal === "strip";
    await startSettingsApp(root, devSettingsBackend(sample, params.has("stress"), link, failSave, params.get("bootproblem")), { storage: null, typed: devTyped(sample, params.has("stress")), initial: page ? migrate(params.get("tab") ? `${page}/${params.get("tab")}` : page) : null });
    if (failSave) {
      const sw = root.querySelector<HTMLButtonElement>(".switch");
      if (refusal === "1") sw?.focus();
      sw?.click();
    }
    // The layout check (scripts/check-settings-layout.sh) reads the rows once the window is drawn.
    const measure = params.get("measure");
    if (measure) {
      const { reportLayout, reportTabFocus } = await import("./devpanel.ts");
      measure === "tabfocus" ? reportTabFocus(root) : reportLayout(root, measure, params.has("stress"), params.has("forget"));
    }
    return;
  }

  // Settings → Devices (sub-project G2). On the dev server `settings.html?linkdev=on` (or off, empty, problem, note) draws the section from a stand-in.
  const linkdev = import.meta.env.DEV ? new URLSearchParams(location.search).get("linkdev") : null;
  const link = linkdev ? (await import("../link/devseed")).devBackend(linkdev) : bridgeLinkBackend();
  await startSettingsApp(root, bridgeSettingsBackend(link), { storage: localStorageOrNull(), initial: null });
}

// A start-up failure is logged and shown in the window, never left as a blank window.
void main().catch((err: unknown) => {
  console.error("[notchmeow] settings failed to start", err);
  const note = document.createElement("p");
  note.className = "notice err";
  note.textContent = "Settings couldn't start. Close and reopen this window.";
  root.replaceChildren(note);
});
