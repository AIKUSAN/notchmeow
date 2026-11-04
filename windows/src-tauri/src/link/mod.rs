// The link (sub-project G2): file transfer between the user's own machines. No Tauri type appears anywhere under this folder, so a test binary can run it (docs/LINK-CONTRACT.md).
// The pure rules are ports of tests/fixtures/link/reference.py and are replayed against tests/fixtures/link/; everything that touches a socket, the credential store or the disk is
// added by the tasks that need it. Each task adds its module on the marker line.

pub mod bytes;
pub mod noise;
pub mod frames;
pub mod name;
pub mod flow;
pub mod pairing;
pub mod cards;
pub mod directory;
pub mod identity;
pub mod keystore;
pub mod settings;
pub mod files;
pub mod channel;
pub mod pair_run;
pub mod transfer;
pub mod discovery;
pub mod mdns;
pub mod restart;
pub mod net;
pub mod service;
// MODULES: add new modules above this line

#[cfg(test)]
mod conformance;

#[cfg(test)]
pub(crate) mod testutil;
