// Focus awareness, the Rust side: which app is in front when a permission request arrives. The read itself is platform code (`platform::foreground_app`); the page compares the
// answer with the request's host and drops it. The name is never logged, stored or sent anywhere.

/// The file name of a process image path: what follows the last `\` or `/`. None when there is none (an empty path, or one that ends in a separator).
#[cfg_attr(not(windows), allow(dead_code))]
pub fn image_base_name(full: &str) -> Option<String> {
    let name = full.rsplit(['\\', '/']).next().unwrap_or("");
    (!name.is_empty()).then(|| name.to_string())
}

/// Which foreground read this system has: "windows" (the process image name), "x11" (the active window's class) or "none" (Wayland: nothing can be read).
pub fn kind(windows: bool, pointer_feed: bool) -> &'static str {
    if windows {
        "windows"
    } else if pointer_feed {
        "x11"
    } else {
        "none"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_image_name_is_the_last_segment_of_either_kind_of_path() {
        assert_eq!(image_base_name(r"C:\Program Files\Microsoft VS Code\Code.exe"), Some("Code.exe".to_string()));
        assert_eq!(image_base_name("/usr/bin/kitty"), Some("kitty".to_string()));
        assert_eq!(image_base_name("Code.exe"), Some("Code.exe".to_string()));
        assert_eq!(image_base_name(""), None);
        assert_eq!(image_base_name(r"C:\dir\"), None);
    }

    #[test]
    fn the_foreground_kind_names_the_read_this_system_has() {
        assert_eq!(kind(true, false), "windows");
        assert_eq!(kind(false, true), "x11");
        assert_eq!(kind(false, false), "none");
    }
}
