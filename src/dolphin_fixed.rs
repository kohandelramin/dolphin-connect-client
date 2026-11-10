//! Dolphin Connect (owner decision D21): the fixed password every app shares, so a technician connects without the
//! customer's Accept when the portal allows it (rules: src/dolphin_fixed_core.rs).
//!
//! The value is not the owner's password itself but HMAC-SHA256(password, context) in hex, written at build time by
//! dolphin/gen_profile.py from the `DOLPHIN_FIXED_PASSWORD` secret into the git-ignored src/dolphin_fixed_generated.rs.
//! It is stored XOR-masked with two random pads and recovered here at run time. That is obfuscation, not encryption:
//! the app must be able to recover the value, so anyone with the exe and a debugger can too. The real protection is
//! the check that the connecting peer is the technician the portal authorized (src/dolphin_fixed_core.rs), and the
//! portal cutting any connection it did not authorize. Never log the value or a hash of it.
use crate::dolphin_fixed_core::{self as core, Gate, Pushed};
use hbb_common::{
    config::{self, Config},
    sha2::{Digest, Sha256},
};

include!("dolphin_fixed_generated.rs");

fn secret() -> Option<String> {
    // black_box keeps the optimizer from folding the three static arrays back into the plain value at build time.
    let masked: &[u8] = std::hint::black_box(&FIXED_MASKED[..]);
    let pad_a: &[u8] = std::hint::black_box(&FIXED_PAD_A[..]);
    let pad_b: &[u8] = std::hint::black_box(&FIXED_PAD_B[..]);
    core::unmask(masked, pad_a, pad_b)
}

/// Whether this build carries the fixed password (a dev build without the secret does not). Says nothing about it.
pub fn built_in() -> bool {
    !FIXED_MASKED.is_empty()
}

/// The technician app's password for a customer PC when the panel gave none; `None` in a customer app or a build
/// without the value. The customer PC decides whether it counts (src/server/connection.rs).
pub fn technician_password() -> Option<String> {
    if !config::is_outgoing_only() {
        return None;
    }
    secret()
}

/// Customer app: is `presented` (the login's SHA256(SHA256(password + salt) + challenge)) the fixed password?
pub fn presented(salt: &str, challenge: &str, presented: &[u8]) -> bool {
    if !config::is_incoming_only() || presented.is_empty() {
        return false;
    }
    let Some(value) = secret() else {
        return false;
    };
    let mut h1 = Sha256::new();
    h1.update(value.as_bytes());
    h1.update(salt.as_bytes());
    let h1 = h1.finalize();
    let mut h2 = Sha256::new();
    h2.update(&h1[..]);
    h2.update(challenge.as_bytes());
    core::constant_time_eq(&h2.finalize()[..], presented)
}

/// The gate as the portal's options stand now (the heartbeat writes them in this same server process).
pub fn gate_now(peer_id: &str) -> Gate {
    let fixed = Config::get_option(core::FIXED_OPTION);
    let approve_mode = Config::get_option(core::APPROVE_MODE_OPTION);
    let portal_down = Config::get_option(core::PORTAL_DOWN_OPTION);
    let tech_id = Config::get_option(core::TECH_ID_OPTION);
    let tech_until = Config::get_option(core::TECH_UNTIL_OPTION);
    let pushed = Pushed {
        fixed: &fixed,
        approve_mode: &approve_mode,
        portal_down: &portal_down,
        tech_id: &tech_id,
        tech_until: &tech_until,
    };
    core::gate(&pushed, peer_id, hbb_common::get_time() / 1000)
}
