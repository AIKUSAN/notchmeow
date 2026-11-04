// The link's backend inside the app (sub-project G2): Rust's commands and its "link" event. In a plain browser (`npm run dev`, the `?dev` page) the stand-in of mock.ts is used instead.

import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { IS_TAURI } from "../core/bridge";
import { LINK_EMPTY, cleanSnapshot } from "./model.ts";
import type { LinkBackend } from "./model.ts";

const post = (cmd: string, args?: Record<string, unknown>): void => {
  if (!IS_TAURI) return;
  invoke(cmd, args).catch((err) => console.error(`[notchmeow] ${cmd} failed`, err));
};

/** Rust's commands (src-tauri/src/link_cmd.rs). The page holds ids and never a path, a key or an address: `send` takes shelf ids, and Rust finds the files. */
export function bridgeLinkBackend(): LinkBackend {
  return {
    state: async () => (IS_TAURI ? cleanSnapshot(await invoke("link_state")) : LINK_EMPTY),
    onSnapshot: (cb) => {
      let off: (() => void) | null = null;
      let gone = false;
      if (IS_TAURI) {
        void listen<unknown>("link", (e) => cb(cleanSnapshot(e.payload)))
          .then((f) => {
            if (gone) f();
            else off = f;
          })
          .catch((err) => console.error("[notchmeow] link listen failed", err));
      }
      return () => {
        gone = true;
        off?.();
      };
    },
    setVisible: (on) => post("link_set_visible", { on }),
    setName: async (name) => (IS_TAURI ? ((await invoke("link_set_name", { name })) as boolean) : false),
    setDevicesOpen: (open) => post("link_devices_open", { open }),
    setShelfOpen: (open) => post("link_shelf_open", { open }),
    pair: (id) => post("link_pair", { id }),
    answerPair: (yes, shown) => post("link_answer_pair", { yes, shown }),
    respondOffer: (accept, shown) => post("link_respond_offer", { accept, shown }),
    cancelReceiving: (shown) => post("link_cancel_receiving", { shown }),
    dismiss: (shown) => post("link_dismiss", { shown }),
    forget: (id) => post("link_forget", { id }),
    send: (ids, to) => post("link_send", { ids, to }),
    cancelSending: () => post("link_cancel_sending"),
    revealResult: () => post("link_reveal_result"),
    revealFolder: () => post("link_reveal_folder"),
  };
}
