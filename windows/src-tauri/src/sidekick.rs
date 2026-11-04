// The Sidekick's side of the platform (sub-project F1, spec "Away and recap"): the lock, sleep and display news that the desktop cat already receives are told to the island's page
// too, and the page can ask how long the user has been idle. Nothing here polls: the watchers are the platform's own notifications, and the idle time is read only when the page
// asks (on a hook event, when the island opens and on an unlock, never on a timer).

use tauri::{AppHandle, Emitter};

use crate::desktop::AwaySource;
use crate::island;
use crate::sidekick_presence::away_signal;

/// One news of a platform watcher (`platform::watch_away` calls this beside the desktop cat's `away_changed`): the island's page is told the word for it, once.
pub fn away_changed(app: &AppHandle, source: AwaySource, on: bool) {
    let signal = away_signal(source, on, cfg!(windows));
    let _ = app.emit_to(island::WINDOW_LABEL, "sidekick-away", serde_json::json!({ "signal": signal }));
}

/// Seconds since the user's last keyboard or mouse input, or null where the system does not say (a Linux desktop that is not GNOME). It runs off the async threads: on Linux it
/// asks a helper program and waits for it.
#[tauri::command]
pub async fn sidekick_idle_seconds() -> Option<u64> {
    tauri::async_runtime::spawn_blocking(crate::platform::idle_seconds).await.ok().flatten()
}
