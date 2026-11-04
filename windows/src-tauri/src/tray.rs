// Notification-area icon: Open, Shelf, Projects, Cat on the desktop, Settings, Pause, Quit.

use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager};

use crate::island::WINDOW_LABEL;

/// The tray's "Cat on the desktop" item, kept so its words can follow the trip: "Bring the cat home" while the cat is out (sub-project H).
pub struct DesktopItem(pub MenuItem<tauri::Wry>);

pub fn set_desktop_text(app: &AppHandle, out: bool) {
    if let Some(item) = app.try_state::<DesktopItem>() {
        let _ = item.0.set_text(if out { "Bring the cat home" } else { "Cat on the desktop" });
    }
}

/// The tray's "Projects" item, kept so its words can follow the registry: "Projects (N)" with N projects (sub-project P).
pub struct ProjectsItem(pub MenuItem<tauri::Wry>);

/// The Projects item's words: "Projects" with no project, "Projects (N)" with N.
pub fn projects_text(count: u32) -> String {
    if count == 0 {
        "Projects".to_string()
    } else {
        format!("Projects ({count})")
    }
}

#[tauri::command]
pub fn projects_menu_text(app: AppHandle, count: u32) {
    if let Some(item) = app.try_state::<ProjectsItem>() {
        let _ = item.0.set_text(projects_text(count));
    }
}

pub fn build(app: &AppHandle) -> tauri::Result<()> {
    let open = MenuItem::with_id(app, "open", "Open NotchMeow", true, None::<&str>)?;
    let shelf = MenuItem::with_id(app, "shelf", "Shelf", true, None::<&str>)?;
    let projects = MenuItem::with_id(app, "projects", "Projects", true, None::<&str>)?;
    let desktop = MenuItem::with_id(app, "desktop", "Cat on the desktop", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "Settings…", true, None::<&str>)?;
    let pause = MenuItem::with_id(app, "pause", "Pause", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let sep1 = PredefinedMenuItem::separator(app)?;
    let sep2 = PredefinedMenuItem::separator(app)?;

    let menu = Menu::with_items(app, &[&open, &shelf, &desktop, &sep1, &settings, &pause, &sep2, &quit])?;
    // The Projects item goes in right after Shelf (index 2), so the shipped menu literal stays as it is.
    menu.insert(&projects, 2)?;
    app.manage(DesktopItem(desktop));
    app.manage(ProjectsItem(projects));

    let mut builder = TrayIconBuilder::with_id("notchmeow")
        .tooltip("NotchMeow")
        .menu(&menu)
        .on_menu_event(|app: &AppHandle, event| match event.id.as_ref() {
            "quit" => app.exit(0),
            "settings" => crate::show_settings_window(app),
            id => {
                let _ = app.emit_to(WINDOW_LABEL, "tray", id.to_string());
            }
        });

    if let Some(icon) = app.default_window_icon().cloned() {
        builder = builder.icon(icon);
    }

    builder.build(app)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::projects_text;

    #[test]
    fn projects_item_words_follow_the_count() {
        assert_eq!(projects_text(0), "Projects");
        assert_eq!(projects_text(3), "Projects (3)");
    }
}
