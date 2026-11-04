// Test-only helpers for the process environment. Every test thread shares one environment, so a test that changes a variable goes through
// `EnvGuard`, which takes `ENV_LOCK` for its life and puts the variable back when it ends (also on a panic). The tests that read a home-derived
// path without a guard do not assert on the value a guard changes: agent_hooks' `status_at` checks an explicit path and only probes the relay's
// path, and link/files' `default_folder` test checks only the folder's name. Any new test that asserts on the redirected home takes a guard.

use std::ffi::{OsStr, OsString};
use std::sync::{Mutex, MutexGuard};

static ENV_LOCK: Mutex<()> = Mutex::new(());

/// Sets one variable for the test's life, under `ENV_LOCK`, and restores what it was (or removes it) on drop.
pub struct EnvGuard {
    _lock: MutexGuard<'static, ()>,
    key: &'static str,
    previous: Option<OsString>,
}

impl EnvGuard {
    /// Takes the lock (a poisoned one is taken anyway: the guard puts the variable back) and sets the variable.
    pub fn set(key: &'static str, value: impl AsRef<OsStr>) -> EnvGuard {
        let lock = ENV_LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let previous = std::env::var_os(key);
        std::env::set_var(key, value);
        EnvGuard { _lock: lock, key, previous }
    }
}

impl Drop for EnvGuard {
    fn drop(&mut self) {
        match &self.previous {
            Some(value) => std::env::set_var(self.key, value),
            None => std::env::remove_var(self.key),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_variable_the_guard_set_is_removed_when_it_ends() {
        let key = "NM_TESTENV_PROBE";
        {
            let _guard = EnvGuard::set(key, "inside");
            assert_eq!(std::env::var(key).as_deref(), Ok("inside"));
        }
        assert!(std::env::var_os(key).is_none(), "it was not set before, so it is not set after");
    }

    /// A variable that was set before comes back with its old value, not removed.
    #[test]
    fn a_variable_that_was_set_before_is_put_back_to_that_value() {
        let key = "NM_TESTENV_RESTORE";
        std::env::set_var(key, "before");
        {
            let _guard = EnvGuard::set(key, "inside");
            assert_eq!(std::env::var(key).as_deref(), Ok("inside"));
        }
        assert_eq!(std::env::var(key).as_deref(), Ok("before"));
        std::env::remove_var(key);
    }

    /// A test that panics while it holds the guard still puts the variable back, and the next guard can take the (poisoned) lock.
    #[test]
    fn a_panic_while_the_guard_is_held_restores_the_variable() {
        let key = "NM_TESTENV_PANIC";
        let result = std::panic::catch_unwind(|| {
            let _guard = EnvGuard::set(key, "inside");
            panic!("the test failed while the variable was changed");
        });
        assert!(result.is_err());
        assert!(std::env::var_os(key).is_none(), "restored on unwind");
        let _again = EnvGuard::set(key, "next");
        assert_eq!(std::env::var(key).as_deref(), Ok("next"), "a poisoned lock is still taken");
    }
}
