// The link's commands and events (sub-project G2): the thin Tauri layer over `link::service`. The folder `link/` knows no Tauri type; this file is where the service meets the app: it builds
// the service from the app's folders and the system's credential store and mDNS, turns the service's snapshots into the `link` event that the island and the Settings window listen to,
// and exposes the service's calls as commands. Every command only posts a request; the answer is the next snapshot. The page holds ids and never a path, a key or an address: `link_send`
// takes shelf ids and Rust finds the files.

use std::path::PathBuf;
use std::sync::Arc;

use tauri::{AppHandle, Emitter, State};

use crate::link::discovery::Discovery;
use crate::link::files;
use crate::link::keystore::{Keystore, SecretStore, SystemStore};
use crate::link::mdns::Mdns;
use crate::link::service::{Config, Deps, Emit, Service, ShownView, Snapshot};
use crate::{log, platform, settings};

/// The service, as the app manages it.
pub struct LinkHandle(pub Service);

struct TauriEmit(AppHandle);

impl Emit for TauriEmit {
    fn snapshot(&self, s: &Snapshot) {
        let _ = self.0.emit("link", s);
    }
    /// A fixed sentence: never a name, a size, an address or an id.
    fn log(&self, line: &'static str) {
        log::line(line);
    }
}

/// Builds the service. It listens and announces nothing until the user turns Visible on in Settings → Devices.
pub fn init(app: &AppHandle) -> Service {
    let cfg = Config::app(settings::local_dir().join("link.json"), files::default_folder(), crate::link::settings::host_name());
    let store: Arc<dyn SecretStore> = Arc::new(SystemStore::new());
    let discovery: Arc<dyn Discovery> = Arc::new(Mdns::new());
    let deps = Deps { keystore: Arc::new(Keystore::new(store)), discovery, emit: Arc::new(TauriEmit(app.clone())) };
    Service::spawn(|f| { tauri::async_runtime::spawn(f); }, cfg, deps)
}

#[tauri::command]
pub async fn link_state(link: State<'_, LinkHandle>) -> Result<Snapshot, String> {
    link.0.snapshot().await.ok_or_else(|| "the link is not running".to_string())
}

#[tauri::command]
pub fn link_set_visible(link: State<'_, LinkHandle>, on: bool) {
    link.0.set_visible(on);
}

#[tauri::command]
pub async fn link_set_name(link: State<'_, LinkHandle>, name: String) -> Result<bool, String> {
    Ok(link.0.set_device_name(name).await)
}

#[tauri::command]
pub fn link_devices_open(link: State<'_, LinkHandle>, open: bool) {
    link.0.set_devices_open(open);
}

#[tauri::command]
pub fn link_shelf_open(link: State<'_, LinkHandle>, open: bool) {
    link.0.set_shelf_open(open);
}

#[tauri::command]
pub fn link_pair(link: State<'_, LinkHandle>, id: String) {
    link.0.pair(id);
}

#[tauri::command]
pub fn link_answer_pair(link: State<'_, LinkHandle>, yes: bool, shown: Option<ShownView>) {
    link.0.answer_pair(yes, shown);
}

/// The only way an offer is accepted: the page calls it from the Accept button, and nothing else calls it with `true`.
#[tauri::command]
pub fn link_respond_offer(link: State<'_, LinkHandle>, accept: bool, shown: Option<ShownView>) {
    link.0.respond_offer(accept, shown);
}

#[tauri::command]
pub fn link_cancel_receiving(link: State<'_, LinkHandle>, shown: Option<ShownView>) {
    link.0.cancel_receiving(shown);
}

#[tauri::command]
pub fn link_dismiss(link: State<'_, LinkHandle>, shown: Option<ShownView>) {
    link.0.dismiss(shown);
}

#[tauri::command]
pub fn link_forget(link: State<'_, LinkHandle>, id: String) {
    link.0.forget(id);
}

/// "To a device": these shelf items go to this machine, one connection each, each needing the other user's Accept. Rust finds the files from the ids.
#[tauri::command]
pub async fn link_send(link: State<'_, LinkHandle>, ids: Vec<String>, to: String) -> Result<(), String> {
    let paths: Vec<PathBuf> = tauri::async_runtime::spawn_blocking(move || crate::shelf_store().resolve(&ids)).await.map_err(|e| e.to_string())?;
    if !paths.is_empty() {
        link.0.send(paths, to);
    }
    Ok(())
}

#[tauri::command]
pub fn link_cancel_sending(link: State<'_, LinkHandle>) {
    link.0.cancel_sending();
}

/// "Show in folder" on the result card of a saved file.
#[tauri::command]
pub async fn link_reveal_result(link: State<'_, LinkHandle>) -> Result<(), String> {
    if let Some(file) = link.0.result_file().await {
        platform::reveal_file(&file);
    }
    Ok(())
}

/// "Show folder" in Settings → Devices: the folder is made first, so that it can be shown before the first file has come.
#[tauri::command]
pub fn link_reveal_folder() {
    let folder = files::default_folder();
    if !folder.is_absolute() {
        return; // HOME was not set: not a folder to make or to show
    }
    let _ = std::fs::create_dir_all(&folder);
    platform::reveal_folder(&folder.to_string_lossy());
}

/// The Settings window hid: Devices is no longer open, whatever the page last said.
pub fn settings_hidden(app: &AppHandle) {
    use tauri::Manager;
    if let Some(link) = app.try_state::<LinkHandle>() {
        link.0.set_devices_open(false);
    }
}
