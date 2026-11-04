// The Sidekick's presence signals, the pure part (sub-project F1, spec "Away and recap"): which word the app's page gets for a news from the platform's watchers, how long the
// user has been idle by the system's own counters, and how to read GNOME's answer. No state, no I/O, no Tauri: `sidekick.rs` and `platform/` call these.

use crate::desktop::AwaySource;

/// The word the contract's `presenceStep` knows for one news of a platform watcher (`desktop::AwaySource`). Windows reports a lock or unlock and the display going off or on; Linux
/// reports a lock or unlock and, from logind's `PrepareForSleep`, the machine going to sleep or waking, which the watcher calls `Off`. So the same `Off` is the display on Windows and
/// the machine on Linux.
pub fn away_signal(source: AwaySource, on: bool, windows: bool) -> &'static str {
    match (source, on, windows) {
        (AwaySource::Locked, true, _) => "lock",
        (AwaySource::Locked, false, _) => "unlock",
        (AwaySource::Off, true, true) => "displayOff",
        (AwaySource::Off, false, true) => "displayOn",
        (AwaySource::Off, true, false) => "sleep",
        (AwaySource::Off, false, false) => "wake",
    }
}

/// Whether a platform's "the session is back" news is a real unlock. Coming back to a session (Linux: logind's `Active` turning true; Windows: the console or a remote session
/// connecting) shows its lock screen when it was locked, so that news is an unlock only when the session is known not to be locked. A lock state that could not be read
/// (`None`) is not: the failure is toward a late return, never an early one (the recap must not run before the user is back).
pub fn unlock_is_real(locked: Option<bool>) -> bool {
    locked == Some(false)
}

/// The lock state in `WTSINFOEX_LEVEL1_W.SessionFlags`: `WTS_SESSIONSTATE_LOCK` (0) is locked and `WTS_SESSIONSTATE_UNLOCK` (1) is not. Anything else (`WTS_SESSIONSTATE_UNKNOWN`, -1)
/// is None.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn session_locked_from_flags(flags: i32) -> Option<bool> {
    match flags {
        0 => Some(true),
        1 => Some(false),
        _ => None,
    }
}

/// Seconds between the tick of the last input and the tick now. Both are 32-bit millisecond counters (`GetLastInputInfo`, `GetTickCount`) that wrap around every 49.7 days, so the
/// difference wraps too.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn idle_seconds_from_ticks(now: u32, last_input: u32) -> u64 {
    u64::from(now.wrapping_sub(last_input)) / 1000
}

/// What `gdbus call … GetIdletime` prints for GNOME's idle monitor: `(uint64 12345,)`, milliseconds. Anything else is None.
pub fn parse_idle_ms(output: &str) -> Option<u64> {
    let inner = output.trim().strip_prefix('(')?.strip_suffix(')')?;
    let inner = inner.strip_suffix(',').unwrap_or(inner).trim();
    inner.strip_prefix("uint64 ")?.trim().parse().ok()
}

/// The most a text put on the clipboard for the Sidekick may hold: the paths of the files dropped on an agent's cat, on one line. It is a few paths, never a way to move data.
pub const CLIPBOARD_MAX_BYTES: usize = 32_768;

/// Whether a text may be put on the clipboard: not empty, not over `CLIPBOARD_MAX_BYTES`, and no NUL (a C string would end there, and the Windows clipboard's text is one).
pub fn clipboard_text_ok(text: &str) -> bool {
    !text.is_empty() && text.len() <= CLIPBOARD_MAX_BYTES && !text.contains('\0')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_short_text_without_a_nul_goes_on_the_clipboard() {
        assert!(clipboard_text_ok("C:\\work\\a.txt"));
        assert!(clipboard_text_ok("/home/me/a.txt '/home/me/b c.txt'"));
        assert!(clipboard_text_ok(&"é".repeat(16_000)), "32000 bytes");
        assert!(!clipboard_text_ok(""));
        assert!(!clipboard_text_ok("a\0b"));
        assert!(!clipboard_text_ok(&"x".repeat(CLIPBOARD_MAX_BYTES + 1)));
        assert!(clipboard_text_ok(&"x".repeat(CLIPBOARD_MAX_BYTES)));
    }

    #[test]
    fn every_news_of_a_watcher_is_a_word_the_presence_rule_knows() {
        let known = ["lock", "unlock", "sleep", "wake", "displayOff", "displayOn"];
        for source in [AwaySource::Locked, AwaySource::Off] {
            for on in [true, false] {
                for windows in [true, false] {
                    let word = away_signal(source, on, windows);
                    assert!(known.contains(&word), "{word}");
                }
            }
        }
        assert_eq!(away_signal(AwaySource::Locked, true, true), "lock");
        assert_eq!(away_signal(AwaySource::Locked, false, false), "unlock");
        assert_eq!(away_signal(AwaySource::Off, true, true), "displayOff", "Windows: the display went off");
        assert_eq!(away_signal(AwaySource::Off, false, true), "displayOn");
        assert_eq!(away_signal(AwaySource::Off, true, false), "sleep", "Linux: the machine is going to sleep");
        assert_eq!(away_signal(AwaySource::Off, false, false), "wake");
    }

    #[test]
    fn idle_seconds_are_whole_seconds_and_survive_the_counter_wrapping() {
        assert_eq!(idle_seconds_from_ticks(10_000, 7_400), 2);
        assert_eq!(idle_seconds_from_ticks(5_000, 5_000), 0);
        assert_eq!(idle_seconds_from_ticks(299_999, 0), 299);
        assert_eq!(idle_seconds_from_ticks(300_000, 0), 300);
        // The tick counter wrapped between the input and now: 1 s before the wrap and 2 s after is 3 s.
        assert_eq!(idle_seconds_from_ticks(2_000, u32::MAX - 999), 3);
    }

    #[test]
    fn an_unlock_is_real_only_when_the_session_is_known_not_to_be_locked() {
        assert!(unlock_is_real(Some(false)));
        assert!(!unlock_is_real(Some(true)), "switching back to a session that is still locked shows its lock screen");
        assert!(!unlock_is_real(None), "a lock state that cannot be read is not an unlock: a late return, never an early one");
    }

    #[test]
    fn the_session_flags_of_windows_say_locked_unlocked_or_nothing() {
        assert_eq!(session_locked_from_flags(0), Some(true));
        assert_eq!(session_locked_from_flags(1), Some(false));
        assert_eq!(session_locked_from_flags(-1), None, "WTS_SESSIONSTATE_UNKNOWN");
        assert_eq!(session_locked_from_flags(2), None);
    }

    #[test]
    fn gnomes_answer_is_read_and_anything_else_is_nothing() {
        assert_eq!(parse_idle_ms("(uint64 12345,)\n"), Some(12345));
        assert_eq!(parse_idle_ms("(uint64 0,)"), Some(0));
        assert_eq!(parse_idle_ms("  (uint64 300000,)  "), Some(300_000));
        for odd in ["", "()", "(,)", "(uint64 ,)", "(uint64 -5,)", "(int32 5,)", "(uint64 5, 6)", "Error: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown", "uint64 5", "(uint64 99999999999999999999,)"] {
            assert_eq!(parse_idle_ms(odd), None, "{odd:?}");
        }
    }
}
