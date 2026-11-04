// When the machine-list daemon dies, when it comes back (sub-project G2b). `mdns-sd` runs its daemon on a thread of its own; if that thread ends (a socket error, a network that went away for
// good) the daemon is gone for good too, and the machine list would stay stale and this machine unannounced until the user toggled Visible. `mdns.rs` notices the end and asks this rule how long
// to wait before it makes the daemon again. The rule is pure: it is fed with what happened and a clock (milliseconds, any origin) and answers with a wait, or with nothing.
//
// The wait grows (1 s, 5 s, 30 s, then every minute for as long as the daemon is wanted), so that a machine whose network is down is tried a few times quickly and then costs one attempt a
// minute, and a daemon that dies at once, over and over, never gets a fast retry loop. A daemon that stayed up for a minute counts as healthy: its next death starts the table again. Nothing is
// ever asked for while the daemon is not wanted (Visible off and nobody looking at Devices or the shelf: `mdns.rs` says so with `set_wanted(false)`).
//
// The Mac twin is `LinkRestart.swift` (the same table; `scripts/link-tests/rust-wiring.test.mjs` reads its numbers).

/// The first three waits.
pub const DELAYS_MS: [u64; 3] = [1_000, 5_000, 30_000];
/// Every wait after those.
pub const STEADY_MS: u64 = 60_000;
/// A daemon that ran this long before it died starts the table again.
pub const STABLE_MS: u64 = 60_000;

#[derive(Debug, Default, Clone)]
pub struct Restarter {
    wanted: bool,
    failures: usize,
    up_since: Option<u64>,
}

impl Restarter {
    pub fn new() -> Restarter {
        Restarter::default()
    }

    /// Whether anything needs the daemon (an advert, a search). Turning it off forgets the table and the daemon's age.
    pub fn set_wanted(&mut self, wanted: bool) {
        self.wanted = wanted;
        if !wanted {
            self.failures = 0;
            self.up_since = None;
        }
    }

    /// A daemon is up (the first one or a restart).
    pub fn started(&mut self, now_ms: u64) {
        self.up_since = Some(now_ms);
    }

    /// The daemon died. The wait before making another, in milliseconds, or None when nothing needs one.
    pub fn died(&mut self, now_ms: u64) -> Option<u64> {
        if let Some(since) = self.up_since.take() {
            if now_ms.saturating_sub(since) >= STABLE_MS {
                self.failures = 0;
            }
        }
        self.next()
    }

    /// A restart could not make a daemon at all: the next wait.
    pub fn failed_restart(&mut self) -> Option<u64> {
        self.up_since = None;
        self.next()
    }

    fn next(&mut self) -> Option<u64> {
        if !self.wanted {
            return None;
        }
        let wait = DELAYS_MS.get(self.failures).copied().unwrap_or(STEADY_MS);
        self.failures = self.failures.saturating_add(1);
        Some(wait)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wanted() -> Restarter {
        let mut r = Restarter::new();
        r.set_wanted(true);
        r
    }

    #[test]
    fn nothing_is_scheduled_for_a_daemon_nobody_wants() {
        let mut r = Restarter::new();
        assert_eq!(r.died(0), None, "never wanted");
        assert_eq!(r.failed_restart(), None);
        let mut r = wanted();
        r.set_wanted(false);
        assert_eq!(r.died(10), None, "no longer wanted");
        assert_eq!(r.failed_restart(), None);
    }

    #[test]
    fn the_waits_are_one_second_five_thirty_and_then_every_minute() {
        let mut r = wanted();
        r.started(0);
        assert_eq!(r.died(100), Some(1_000));
        let rest: Vec<u64> = (0..6).map(|_| r.failed_restart().unwrap()).collect();
        assert_eq!(rest, [5_000, 30_000, 60_000, 60_000, 60_000, 60_000]);
    }

    #[test]
    fn a_daemon_that_dies_at_once_again_and_again_never_gets_a_fast_loop() {
        let mut r = wanted();
        let mut t = 0;
        let mut waits = Vec::new();
        for _ in 0..6 {
            r.started(t);
            let w = r.died(t + 10).unwrap();
            waits.push(w);
            t += 10 + w;
        }
        assert_eq!(waits, [1_000, 5_000, 30_000, 60_000, 60_000, 60_000]);
    }

    #[test]
    fn a_daemon_that_stayed_up_a_minute_starts_the_table_again() {
        let mut r = wanted();
        r.started(0);
        assert_eq!(r.died(10), Some(1_000));
        assert_eq!(r.failed_restart(), Some(5_000));
        r.started(200_000);
        assert_eq!(r.died(259_999), Some(30_000), "59.999 s is not a minute");
        r.started(300_000);
        assert_eq!(r.died(360_000), Some(1_000), "a minute is");
        r.started(400_000);
        assert_eq!(r.died(1_400_000), Some(1_000), "and so is a long life");
    }

    #[test]
    fn turning_the_wish_off_forgets_the_table() {
        let mut r = wanted();
        r.started(0);
        r.died(10);
        r.failed_restart();
        r.set_wanted(false);
        r.set_wanted(true);
        assert_eq!(r.died(20), Some(1_000));
    }

    #[test]
    fn no_wait_is_shorter_than_a_second_or_longer_than_a_minute() {
        let mut r = wanted();
        for _ in 0..200 {
            let w = r.failed_restart().unwrap();
            assert!((1_000..=60_000).contains(&w), "{w}");
        }
    }
}
