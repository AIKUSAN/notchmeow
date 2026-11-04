// What the link saves and how it is cleaned (sub-project G2): whether this machine is visible on the network, and the name the other machines show for it. Two values in `link.json` in the
// app's data folder, written by Rust alone (the page never saves them, so a settings save from the page can never drop them): `visible` (a boolean, **off until the user turns it on** in
// Settings → Devices: until then there is no listener, no advert and no firewall prompt) and `deviceName` (text). Secrets are not here: the keys and the paired machines are in the credential
// store (`keystore.rs`). The Mac's twin is LinkSettings.swift (`link.visible` and `link.deviceName` in UserDefaults).

use std::path::Path;

use serde_json::{json, Value};

use super::frames::{device_name, DEVICE_NAME_MAX};
use super::name::{is_bad_category, is_invisible, is_space};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkSettings {
    pub visible: bool,
    pub device_name: String,
}

/// `true` only for the boolean true: the number 1 and the text "true" are off (a settings file can be hand-edited).
pub fn is_true(v: Option<&Value>) -> bool {
    matches!(v, Some(Value::Bool(true)))
}

/// A name that the other machine's card would accept (`frames::device_name`: 1 to 63 bytes, no control, format or invisible character, no space at either end), or None.
pub fn valid_name(v: Option<&Value>) -> Option<String> {
    device_name(v?.as_str()?.as_bytes()).ok()
}

/// The name offered by default, from the computer's own name ("Desk PC"): the characters a card would refuse are dropped, the ends trimmed, the rest cut to 63 bytes at a character.
/// A name with nothing left is "Computer".
pub fn default_name(host: &str) -> String {
    let kept: Vec<char> = host.chars().filter(|&c| !is_bad_category(c) && !is_invisible(c)).collect();
    let (mut start, mut end) = (0, kept.len());
    while start < end && is_space(kept[start]) {
        start += 1;
    }
    while end > start && is_space(kept[end - 1]) {
        end -= 1;
    }
    let (mut out, mut bytes) = (String::new(), 0);
    for &c in &kept[start..end] {
        if bytes + c.len_utf8() > DEVICE_NAME_MAX {
            break;
        }
        out.push(c);
        bytes += c.len_utf8();
    }
    let out = out.trim_end_matches(is_space).to_string();
    if out.is_empty() { "Computer".to_string() } else { out }
}

/// Everything stored, cleaned: visible only when exactly `true`, the name when it passes `valid_name`, else the default from `host`. Never fails.
pub fn clean(raw: &Value, host: &str) -> LinkSettings {
    LinkSettings { visible: is_true(raw.get("visible")), device_name: valid_name(raw.get("deviceName")).unwrap_or_else(|| default_name(host)) }
}

pub fn load(path: &Path, host: &str) -> LinkSettings {
    let raw = std::fs::read(path).ok().and_then(|b| serde_json::from_slice::<Value>(&b).ok()).unwrap_or(Value::Null);
    clean(&raw, host)
}

/// Writes the file whole through a temporary one, so a crash leaves the old file or the new one, never half of one.
pub fn save(path: &Path, s: &LinkSettings) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_vec_pretty(&json!({"visible": s.visible, "deviceName": s.device_name}))?)?;
    std::fs::rename(&tmp, path)
}

/// This computer's name, for the default device name only. Windows: `COMPUTERNAME`. Linux: the kernel's hostname. It is read at launch for that one purpose and nowhere else
/// (`scripts/link-tests/rust-wiring.test.mjs`, the test "this computer's name is read in one place", pins that no other file of the link reads it, and the pictures never do).
pub fn host_name() -> String {
    #[cfg(windows)]
    {
        std::env::var("COMPUTERNAME").unwrap_or_default()
    }
    #[cfg(not(windows))]
    {
        std::fs::read_to_string("/proc/sys/kernel/hostname").or_else(|_| std::fs::read_to_string("/etc/hostname")).unwrap_or_default().trim().to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(tag: &str) -> std::path::PathBuf {
        static N: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let dir = std::env::temp_dir().join(format!("notchmeow-linkset-{tag}-{}-{}", std::process::id(), N.fetch_add(1, std::sync::atomic::Ordering::Relaxed)));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn visible_is_off_unless_it_is_exactly_true() {
        for v in [json!(null), json!(1), json!("true"), json!([true]), json!({}), json!(0)] {
            assert!(!clean(&json!({"visible": v}), "Desk PC").visible, "{v}");
        }
        assert!(!clean(&json!({}), "Desk PC").visible && !clean(&Value::Null, "Desk PC").visible, "off by default");
        assert!(clean(&json!({"visible": true}), "Desk PC").visible);
    }

    #[test]
    fn a_stored_name_is_kept_when_a_card_would_accept_it_and_replaced_by_the_default_when_not() {
        assert_eq!(clean(&json!({"deviceName": "Studio PC"}), "Desk PC").device_name, "Studio PC");
        for bad in [json!(""), json!(" padded"), json!("a\nb"), json!("a\u{202e}b"), json!("x".repeat(64)), json!(7), json!(null)] {
            assert_eq!(clean(&json!({"deviceName": bad}), "Desk PC").device_name, "Desk PC", "{bad}");
        }
        assert_eq!(clean(&json!({"deviceName": "x".repeat(63)}), "Desk PC").device_name.len(), 63);
    }

    #[test]
    fn the_default_name_is_the_computers_cleaned() {
        assert_eq!(default_name("Desk PC"), "Desk PC");
        assert_eq!(default_name("  Sam's MacBook Pro  "), "Sam's MacBook Pro");
        assert_eq!(default_name("Desk\u{202e}PC\n"), "DeskPC");
        assert_eq!(default_name(""), "Computer");
        assert_eq!(default_name("\u{200b}\u{200b}"), "Computer");
        let long = default_name(&"é".repeat(60));
        assert!(long.len() <= 63 && long.chars().all(|c| c == 'é') && long.len() == 62, "cut at a character, not in the middle of one: {} bytes", long.len());
        assert!(device_name(default_name("a  ").as_bytes()).is_ok());
    }

    #[test]
    fn what_is_saved_is_what_is_loaded_and_a_damaged_file_is_the_default() {
        let dir = temp("save");
        let path = dir.join("link.json");
        assert_eq!(load(&path, "Desk PC"), LinkSettings { visible: false, device_name: "Desk PC".into() });
        let s = LinkSettings { visible: true, device_name: "Studio PC".into() };
        save(&path, &s).unwrap();
        assert_eq!(load(&path, "Desk PC"), s);
        std::fs::write(&path, "{ not json").unwrap();
        assert_eq!(load(&path, "Desk PC"), LinkSettings { visible: false, device_name: "Desk PC".into() });
        assert!(!dir.join("link.json.tmp").exists());
    }
}
