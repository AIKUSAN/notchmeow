// Finding the other machines (sub-project G2, docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md, "Discovery"): the advert of this machine and the browser for the others, both
// `_notchmeow._tcp` over mDNS. The service talks to this small trait, so everything above it is tested without a network; `Mdns` (the `mdns-sd` crate, pure Rust, no Avahi needed) is the
// one implementation that touches the network. The advert carries only `v`, `id` and `name`; it gives a machine something to show in a list and nothing more: only a paired key gets a session.

use std::net::SocketAddr;
use std::sync::Arc;

use super::frames::Advert;

pub const SERVICE_TYPE: &str = "_notchmeow._tcp.local.";

/// A machine seen on the network: what its advert says, and where to connect to it.
#[derive(Clone, PartialEq, Eq)]
pub struct Found {
    pub advert: Advert,
    pub addr: SocketAddr,
}

impl std::fmt::Debug for Found {
    /// A fixed label: the address is never printed, and the advert's own `Debug` hides its id and name.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Found").finish_non_exhaustive()
    }
}

pub type OnResults = Arc<dyn Fn(Vec<Found>) + Send + Sync>;

pub trait Discovery: Send + Sync + 'static {
    /// Announces this machine (or announces it again under a new name). `Err` is a sentence for Settings → Devices.
    fn advertise(&self, id: &str, name: &str, port: u16) -> Result<(), String>;
    fn stop_advertising(&self);
    /// Starts looking for the others; `on_results` gets the whole list every time it changes. An advert that does not pass `parse_txt` (version, id, name, this machine's own id) is not listed.
    fn browse(&self, own_id: &str, on_results: OnResults) -> Result<(), String>;
    /// Stops looking. When it returns no `on_results` is running and none will be called. It **blocks until an `on_results` that is in flight has returned**, so the caller must never call it while
    /// holding a lock that the callback also takes. The callback itself may call it (it does not wait for itself).
    fn stop_browsing(&self);
}

#[cfg(test)]
mod tests {
    use super::*;

    // The address, the id and the name of a machine on the network are never printed, whatever prints a `Found`.
    #[test]
    fn a_found_machine_prints_as_a_fixed_label() {
        let id = "0123456789abcdef0123456789abcdef";
        let found = Found { advert: Advert { id: id.into(), name: "Desk PC".into() }, addr: "192.168.7.42:51234".parse().unwrap() };
        let printed = format!("{found:?} {:#?}", Some(found.clone()));
        for secret in ["192.168", "51234", "0123456789", "Desk"] {
            assert!(!printed.contains(secret), "{secret} must not be printed");
        }
        assert!(printed.contains("Found"));
    }
}
