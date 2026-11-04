// API keys live in the Windows Credential Manager or, on Linux, the Secret
// Service (GNOME Keyring, KWallet) — never on disk and never in the front end — the island can only ask whether a key is present.

use keyring::Entry;

const SERVICE: &str = "io.github.aikusan.notchmeow";

/// Every key NotchMeow may store. Anything outside this list is refused.
pub const KNOWN_KEYS: &[&str] = &[
    "anthropic-api-key",
    "google-api-key",
    "openai-api-key",
    "n8n-url",
    "n8n-api-key",
    "vercel-token",
    "github-token",
    "stripe-api-key",
    "resend-api-key",
    "notion-api-key",
    "calcom-api-key",
];

/// The server added with Settings → AI → Add server… keeps its key (when it needs one) as
/// `custom-server-key.<serverId>`. The contract allows several added servers, one item each.
const CUSTOM_SERVER_KEY_PREFIX: &str = "custom-server-key.";

/// `^[a-z0-9-]{1,32}$`, checked by hand: no regex crate, and a trailing newline can't slip past a `$`.
fn is_server_id(id: &str) -> bool {
    (1..=32).contains(&id.len()) && id.bytes().all(|b| matches!(b, b'a'..=b'z' | b'0'..=b'9' | b'-'))
}

/// A fixed key, or the prefix with a valid server id. The bare prefix is not a key.
fn is_allowed(key: &str) -> bool {
    KNOWN_KEYS.contains(&key) || key.strip_prefix(CUSTOM_SERVER_KEY_PREFIX).is_some_and(is_server_id)
}

fn entry(key: &str) -> Option<Entry> {
    if !is_allowed(key) {
        return None;
    }
    Entry::new(SERVICE, key).ok()
}

pub fn get(key: &str) -> Option<String> {
    entry(key)?.get_password().ok().filter(|v| !v.is_empty())
}

/// An empty value is a removal, and a removal that failed is a failure: the credential may still be there.
pub fn set(key: &str, value: &str) -> Result<(), String> {
    if value.is_empty() {
        return clear(key);
    }
    let entry = entry(key).ok_or_else(|| format!("unknown key {key}"))?;
    entry.set_password(value).map_err(|e| e.to_string())
}

pub fn clear(key: &str) -> Result<(), String> {
    let entry = entry(key).ok_or_else(|| format!("unknown key {key}"))?;
    deleted(entry.delete_credential())
}

/// A delete that found nothing to delete is done; any other failure is not.
fn deleted(result: Result<(), keyring::Error>) -> Result<(), String> {
    match result {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

/// Puts a failed `op` ("set" or "clear") in the log in a fixed sentence: the key's name when it is on the allow-list, never its value, and never the store's own text
/// (which can carry a path or a bus name). The result goes back unchanged.
pub fn logged<T>(op: &str, key: &str, result: Result<T, String>) -> Result<T, String> {
    if result.is_err() {
        let name = if is_allowed(key) { key } else { "a key that is not allowed" };
        crate::log::line(format!("credential store: {op} failed for {name}"));
    }
    result
}

pub fn present(key: &str) -> bool {
    get(key).is_some()
}

/// What the Settings window may learn about a key. Unreadable is its own answer: a store that
/// fails is never shown as "no key yet".
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Presence {
    Present,
    Absent,
    Unreadable,
}

/// Maps one store answer to a presence. Only a value, or a missing item, is an answer; every
/// other failure (no store, a refused or broken store, bad bytes) is unreadable.
pub fn classify(result: Result<String, keyring::Error>) -> Presence {
    match result {
        Ok(v) if !v.is_empty() => Presence::Present,
        Ok(_) | Err(keyring::Error::NoEntry) => Presence::Absent,
        Err(_) => Presence::Unreadable,
    }
}

/// The presence of a key for the Settings window. Keys this app never stores are absent.
pub fn presence(key: &str) -> Presence {
    if !is_allowed(key) {
        return Presence::Absent;
    }
    match Entry::new(SERVICE, key) {
        Ok(entry) => classify(entry.get_password()),
        Err(_) => Presence::Unreadable,
    }
}

#[cfg(test)]
mod tests {
    use super::{classify, clear, deleted, is_allowed, logged, presence, set, Presence, KNOWN_KEYS};

    /// Each store answer maps to one presence: a value is present, an empty value or a missing
    /// item is absent, and every other failure (no store, a locked or broken store, bad bytes) is
    /// unreadable — never taken for an absent key.
    #[test]
    fn classify_maps_each_store_answer() {
        assert_eq!(classify(Ok("x".to_string())), Presence::Present);
        assert_eq!(classify(Ok(String::new())), Presence::Absent);
        assert_eq!(classify(Err(keyring::Error::NoEntry)), Presence::Absent);
        let io = || Box::new(std::io::Error::other("store refused")) as Box<dyn std::error::Error + Send + Sync>;
        assert_eq!(classify(Err(keyring::Error::NoStorageAccess(io()))), Presence::Unreadable);
        assert_eq!(classify(Err(keyring::Error::PlatformFailure(io()))), Presence::Unreadable);
        assert_eq!(classify(Err(keyring::Error::BadEncoding(vec![0xff]))), Presence::Unreadable);
        assert_eq!(classify(Err(keyring::Error::Ambiguous(Vec::new()))), Presence::Unreadable);
    }

    /// A key the app never stores is absent, without asking the store at all.
    #[test]
    fn presence_of_a_key_outside_the_allow_list_is_absent() {
        assert_eq!(presence("not-a-key"), Presence::Absent);
        assert_eq!(presence("custom-server-key."), Presence::Absent);
    }

    /// Every keychain item the AI catalog names can be stored: the fixed keys as they are, the
    /// added server's under its id.
    #[test]
    fn every_ai_key_in_the_catalog_is_allowed() {
        for p in crate::ai::catalog::PROVIDERS {
            if let Some(name) = crate::ai::catalog::keychain_name(p.id) {
                assert!(is_allowed(&name), "{name} is missing from KNOWN_KEYS");
            }
        }
        assert!(KNOWN_KEYS.contains(&"openai-api-key"));
    }

    /// providers.json's `custom-server-key` is a prefix: `custom-server-key.<serverId>`, with
    /// `serverId` matching `^[a-z0-9-]{1,32}$`.
    #[test]
    fn an_added_servers_key_needs_a_valid_server_id() {
        for ok in ["custom-server-key.default", "custom-server-key.a", "custom-server-key.studio-2", "custom-server-key.0-9"] {
            assert!(is_allowed(ok), "{ok}");
        }
        assert!(is_allowed(&format!("custom-server-key.{}", "a".repeat(32))), "32 characters is the longest id");
        for bad in [
            "custom-server-key",
            "custom-server-key.",
            "custom-server-key.../x",
            "custom-server-key.Studio",
            "custom-server-key.st\u{fc}dio",
            "custom-server-key.\u{663}",
            "custom-server-key.a_b",
            "custom-server-key.a.b",
            "custom-server-key.default\n",
            "custom-server-key.default ",
            "custom-server-key-default",
            "Custom-server-key.default",
        ] {
            assert!(!is_allowed(bad), "{bad:?} must be refused");
        }
        assert!(!is_allowed(&format!("custom-server-key.{}", "a".repeat(33))), "33 characters is one too many");
    }

    /// A refused key never reaches the keychain.
    #[test]
    fn set_and_clear_refuse_a_key_that_is_not_allowed() {
        for bad in ["custom-server-key.", "custom-server-key.../x", "custom-server-key.UPPER", "custom-server-key", "not-a-key"] {
            assert!(set(bad, "secret").is_err(), "set {bad}");
            assert!(clear(bad).is_err(), "clear {bad}");
        }
    }

    /// Removing a credential that is not there is done; a store that refuses is not (an empty `set` goes through the same rule, so it never reports Ok for a
    /// credential that may still be stored).
    #[test]
    fn a_delete_that_fails_is_an_error_and_one_that_found_nothing_is_not() {
        assert_eq!(deleted(Ok(())), Ok(()));
        assert_eq!(deleted(Err(keyring::Error::NoEntry)), Ok(()));
        let refused = Box::new(std::io::Error::other("store refused")) as Box<dyn std::error::Error + Send + Sync>;
        assert!(deleted(Err(keyring::Error::NoStorageAccess(refused))).is_err());
    }

    /// A failed key write or removal reaches the log by the key's name, in a fixed sentence: not the value, not the store's text, and no name for a key that is not
    /// on the allow-list.
    #[test]
    fn a_failed_key_change_is_logged_in_a_fixed_sentence() {
        let failed: Result<(), String> = Err("Platform secure storage failure: /run/user/1000/bus hunter2".into());
        assert!(logged("set", "stripe-api-key", failed.clone()).is_err(), "the result goes back unchanged");
        assert!(logged("clear", "../etc/passwd", failed).is_err());
        assert!(logged("set", "stripe-api-key", Ok(())).is_ok());
        let lines = crate::log::CAPTURED.lock().unwrap().iter().filter(|l| l.starts_with("credential store:")).cloned().collect::<Vec<_>>();
        assert!(lines.contains(&"credential store: set failed for stripe-api-key".to_string()), "{lines:?}");
        assert!(lines.contains(&"credential store: clear failed for a key that is not allowed".to_string()), "{lines:?}");
        assert!(lines.iter().all(|l| !l.contains("hunter2") && !l.contains("/run/")), "{lines:?}");
        assert_eq!(lines.len(), 2, "a success logs nothing: {lines:?}");
    }
}
