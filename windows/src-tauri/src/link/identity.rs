// Who this machine is and who it has paired with (sub-project G2). The static private key and the device id come from the credential store (`keystore.rs`); a conversation is given them as an
// `Identity`, and the machines it has paired with as `Peer`s.

/// This machine, as a conversation sees it. `key` is the static private key: it never reaches a log, a file or the page (`Debug` hides it).
#[derive(Clone)]
pub struct Identity {
    /// 32 lower-case hex digits, never all zero.
    pub device_id: String,
    /// What the other machine's card shows (`frames::device_name` accepts it).
    pub name: String,
    pub key: [u8; 32],
    pub public: [u8; 32],
}

impl std::fmt::Debug for Identity {
    /// A fixed label and the hidden key: the id, the name and the public key are never printed.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Identity").field("key", &"(hidden)").finish_non_exhaustive()
    }
}

/// A machine this one has paired with: its device id, the name it gave (authenticated, from its hello), its static public key (64 lower-case hex digits) and when it was paired (seconds).
#[derive(Clone, PartialEq, Eq)]
pub struct Peer {
    pub id: String,
    pub name: String,
    pub key: String,
    pub at: i64,
}

impl std::fmt::Debug for Peer {
    /// A fixed label: the id, the name, the key and the time are never printed.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Peer").finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_debug_print_names_no_id_name_key_or_public_key() {
        let id = "5e".repeat(16);
        let ident = Identity { device_id: id.clone(), name: "Sam's MacBook Pro".into(), key: [0xab; 32], public: [0xcd; 32] };
        let peer = Peer { id: id.clone(), name: "Desk PC".into(), key: "d3".repeat(32), at: 1_700_000_000 };
        let text = format!("{ident:?} {peer:?}");
        for secret in [id.as_str(), "5e5e", "Sam's MacBook Pro", "Desk PC", "d3d3", "cdcd", "171"] {
            assert!(!text.contains(secret), "{secret} in {text}");
        }
        assert!(text.contains("(hidden)"), "{text}");
    }
}
