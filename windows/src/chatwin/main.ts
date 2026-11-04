// Entry point of the chat's pop-out window (sub-project F3a-tauri, Task 9): the island's chat view, full window, over a link that holds the last context the island pushed.
// The page is created hidden at launch (src-tauri/src/lib.rs `create_chat_window`) and does nothing until it is shown: no timer, no frame callback. It talks to the island
// only through Rust's `chat_relay`, and every message it takes is checked first (companion/windowlink.ts).

import "../style.css";
import "../companion/companion.css";
import "./chatwin.css";
import { Bridge, onEvent } from "../core/bridge.ts";
import { State, type Settings } from "../core/state.ts";
import { bridgeStore } from "../companion/store.ts";
import { bridgeChat, forgetDeletedAll, noteInChat, openConversation, startNewChat } from "../companion/session.ts";
import { OPEN_FAILED_NOTE } from "../companion/chrome.ts";
import { isConversationId, windowLink } from "../companion/windowlink.ts";
import { buildPrompt } from "../views/chat.ts";

const root = document.getElementById("chat-root");

async function main(host: HTMLElement) {
  const link = windowLink((msg) => void Bridge.chatRelay("island", msg));
  // The island can show the window the moment the page has loaded, before boot and the mount are done: the two relay listeners are registered first, and a first
  // `chat-window-open` is kept until the chat is mounted (`open`), then played once.
  let open: ((asked: unknown) => void) | null = null;
  let early: { asked: unknown } | null = null;
  await onEvent<{ conversationId?: unknown }>("chat-window-open", (p) => {
    if (open) open(p?.conversationId);
    else early = { asked: p?.conversationId };
  });
  await onEvent<unknown>("chat-msg", (msg) => {
    link.take(msg);
    State.notify();
  });

  const boot = await Bridge.boot();
  if (boot) State.settings = { ...State.settings, ...boot.settings };

  const chat = buildPrompt({ openSettingsWindow: (place) => void Bridge.openSettingsWindow(place), openUrl: (url) => void Bridge.openUrl(url), emote: () => {} }, () => {}, link);
  host.append(chat.el);
  chat.el.classList.add("on");
  chat.sync();

  // The chat view calls State.notify after every change; the window draws then. The island is told the conversation's id when it changes (a save gave it one, or an
  // opened one is shown), so Bring it back and a closed window land on the same conversation.
  let told: string | null = null;
  State.subscribe(() => {
    chat.sync();
    if (State.chatId !== null && State.chatId !== told) {
      told = State.chatId;
      void Bridge.chatRelay("island", { kind: "current", id: told });
    }
  });

  await onEvent<Settings>("settings-changed", (s) => {
    State.settings = { ...State.settings, ...s };
    State.notify();
    // A new brain changes the cloud line, so the model the chat shows is read again (the same as the island's chat).
    void chat.refreshModel();
  });
  await onEvent<unknown>("companion-deleted-all", () => forgetDeletedAll(link, bridgeChat));
  // Rust sends `chat-window-open` only when the window was hidden: the island saved the conversation and handed it over, so the window loads it from its file, whatever it held before. (A window
  // that is already showing is only brought forward; it is never told to open anything.) An id that is not a conversation's is a new chat; a file that cannot be opened is a new chat that says so.
  open = (asked) => {
    void (async () => {
      if (!isConversationId(asked)) startNewChat(link, bridgeChat);
      else if (!(await openConversation(bridgeStore, asked, link, bridgeChat))) {
        startNewChat(link, bridgeChat);
        noteInChat(OPEN_FAILED_NOTE);
      }
      State.notify();
      chat.focus?.();
    })();
  };
  if (early) open((early as { asked: unknown }).asked);
}

if (root) {
  // The dev server's picture route (`chat.html?sample=1&scene=<scene>`): the chat on made-up words and stand-ins, no Tauri and no file. A release build has no such branch.
  const sample = new URLSearchParams(location.search);
  if (import.meta.env.DEV && sample.get("sample") === "1") {
    void import("../companion/devcompanion.ts").then((m) => m.mountChatSample(root, sample.get("scene") ?? ""));
  } else {
    void main(root).catch((err: unknown) => {
      console.error("[notchmeow] the chat window failed to start", err);
      const note = document.createElement("p");
      note.style.cssText = "padding:24px;color:var(--ink)";
      note.textContent = "The chat couldn't start. Close this window and pop the chat out again.";
      root.replaceChildren(note);
    });
  }
}
