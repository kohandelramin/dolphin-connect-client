//! Dolphin Connect (owner decision D21): the rules for the fixed password, standard library only, so CI tests them
//! alone (`rustc --edition 2021 --test src/dolphin_fixed_core.rs`). The value, the hashing and the config reads are in
//! src/dolphin_fixed.rs; the login hook is in src/server/connection.rs (customer) and src/client.rs (technician).
//!
//! The customer app accepts the fixed password only when all of these hold, so the portal keeps the final say:
//! - the portal pushed `dolphin-fixed-password` = "Y" for this PC's organization (only "Y" counts; off is "N" or the
//!   option missing, e.g. a PC that never heard from the portal);
//! - the organization is not in code mode (`approve-mode` "password" never takes it, whatever else was pushed);
//! - the heartbeat reaches the portal now (`dolphin-portal-down` is not "Y"): with the portal away nobody could cut an
//!   unauthorized connection, so the customer's Accept or the one-time password is needed instead;
//! - the connecting peer is the technician the portal authorized for this PC right now (`dolphin-tech-id`, not expired by
//!   `dolphin-tech-until`, the same check and clock allowance as the accept prompt, flutter/lib/dolphin/verify.dart).
//!   The fixed password is the same in every app and the exes are public, so this check, not the password, is what
//!   keeps a stranger who dug the value out of an exe from connecting without the customer's Accept.

/// Pushed by the portal per organization (app/src/lib/engine/policy.ts in the portal repo).
pub const FIXED_OPTION: &str = "dolphin-fixed-password";
pub const TECH_ID_OPTION: &str = "dolphin-tech-id";
pub const TECH_UNTIL_OPTION: &str = "dolphin-tech-until";
pub const PORTAL_DOWN_OPTION: &str = "dolphin-portal-down";
pub const APPROVE_MODE_OPTION: &str = "approve-mode";

/// Same allowance for a PC clock that runs fast as the accept prompt (verify.dart kDolphinClockSkewSeconds, TB-9).
pub const CLOCK_SKEW_SECONDS: i64 = 600;
/// A login with the fixed password may arrive before the portal's word on who may connect: while a connection is open
/// the heartbeat runs every 3 s and brings it. The login waits this long, then counts as refused.
pub const WAIT_MS: u64 = 9_000;
pub const POLL_MS: u64 = 500;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Gate {
    /// Accept the login.
    Allow,
    /// Not yet: the portal's word may still come (authorization, portal back). Refused after [`WAIT_MS`].
    Wait,
    /// Never for this PC as it is set now (off for the organization, or code mode).
    Refuse,
}

/// What the portal pushed, as read from the PC's options.
pub struct Pushed<'a> {
    pub fixed: &'a str,
    pub approve_mode: &'a str,
    pub portal_down: &'a str,
    pub tech_id: &'a str,
    pub tech_until: &'a str,
}

pub fn gate(p: &Pushed, peer_id: &str, now_seconds: i64) -> Gate {
    if p.fixed != "Y" || p.approve_mode == "password" {
        return Gate::Refuse;
    }
    if p.portal_down == "Y" {
        return Gate::Wait;
    }
    // "-" and "0" are the portal's "nobody may connect now"; empty means it never said.
    let named = !p.tech_id.is_empty() && p.tech_id != "-" && p.tech_id != "0";
    let until = p.tech_until.trim().parse::<i64>().unwrap_or(0);
    if named && !peer_id.is_empty() && p.tech_id == peer_id && now_seconds < until + CLOCK_SKEW_SECONDS {
        Gate::Allow
    } else {
        Gate::Wait
    }
}

/// The value from the three arrays the build wrote (dolphin/gen_profile.py `render_fixed_rust`). `None` when the build
/// has no fixed password (empty arrays) or the arrays do not fit together.
pub fn unmask(masked: &[u8], pad_a: &[u8], pad_b: &[u8]) -> Option<String> {
    if masked.is_empty() || masked.len() != pad_a.len() || pad_a.len() != pad_b.len() {
        return None;
    }
    let bytes: Vec<u8> = masked.iter().zip(pad_a).zip(pad_b).map(|((m, a), b)| m ^ a ^ b).collect();
    String::from_utf8(bytes).ok()
}

/// No early exit on the first differing byte.
pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).fold(0u8, |x, (p, q)| x | (p ^ q)) == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: i64 = 1_800_000_000;
    const TECH: &str = "1234567890";

    fn pushed<'a>(fixed: &'a str, mode: &'a str, down: &'a str, id: &'a str, until: &'a str) -> Pushed<'a> {
        Pushed { fixed, approve_mode: mode, portal_down: down, tech_id: id, tech_until: until }
    }

    fn later() -> String {
        (NOW + 3600).to_string()
    }

    #[test]
    fn the_authorized_technician_is_let_in_when_the_portal_turned_it_on() {
        let until = later();
        assert_eq!(gate(&pushed("Y", "both", "", TECH, &until), TECH, NOW), Gate::Allow);
        assert_eq!(gate(&pushed("Y", "click", "", TECH, &until), TECH, NOW), Gate::Allow);
    }

    #[test]
    fn off_or_code_mode_is_refused_at_once() {
        let until = later();
        for fixed in ["", "N", "y", "YES", "-"] {
            assert_eq!(gate(&pushed(fixed, "both", "", TECH, &until), TECH, NOW), Gate::Refuse, "{fixed}");
        }
        // Code mode never takes the fixed password, even if the portal pushed "Y" by mistake.
        assert_eq!(gate(&pushed("Y", "password", "", TECH, &until), TECH, NOW), Gate::Refuse);
    }

    #[test]
    fn another_peer_or_no_authorization_waits_for_the_portal() {
        let until = later();
        assert_eq!(gate(&pushed("Y", "both", "", TECH, &until), "999999999", NOW), Gate::Wait);
        for id in ["", "-", "0"] {
            assert_eq!(gate(&pushed("Y", "both", "", id, &until), id, NOW), Gate::Wait, "{id:?}");
        }
        assert_eq!(gate(&pushed("Y", "both", "", TECH, &until), "", NOW), Gate::Wait);
    }

    #[test]
    fn an_expired_authorization_waits_with_the_prompts_clock_allowance() {
        let past = (NOW - 1).to_string();
        assert_eq!(gate(&pushed("Y", "both", "", TECH, &past), TECH, NOW), Gate::Allow); // within 10 minutes
        let long_past = (NOW - CLOCK_SKEW_SECONDS).to_string();
        assert_eq!(gate(&pushed("Y", "both", "", TECH, &long_past), TECH, NOW), Gate::Wait);
        assert_eq!(gate(&pushed("Y", "both", "", TECH, "garbage"), TECH, NOW), Gate::Wait);
        assert_eq!(gate(&pushed("Y", "both", "", TECH, ""), TECH, NOW), Gate::Wait);
    }

    #[test]
    fn nothing_is_let_in_while_the_portal_cannot_be_reached() {
        let until = later();
        assert_eq!(gate(&pushed("Y", "both", "Y", TECH, &until), TECH, NOW), Gate::Wait);
        assert_eq!(gate(&pushed("Y", "both", "N", TECH, &until), TECH, NOW), Gate::Allow);
    }

    #[test]
    fn the_value_comes_back_from_the_three_arrays() {
        let secret = b"0123456789abcdef";
        let a: Vec<u8> = (0..16u8).map(|i| i.wrapping_mul(37).wrapping_add(11)).collect();
        let b: Vec<u8> = (0..16u8).map(|i| i.wrapping_mul(91).wrapping_add(3)).collect();
        let masked: Vec<u8> = secret.iter().zip(&a).zip(&b).map(|((s, x), y)| s ^ x ^ y).collect();
        assert_ne!(&masked[..], &secret[..]);
        assert_eq!(unmask(&masked, &a, &b).as_deref(), Some("0123456789abcdef"));
    }

    #[test]
    fn a_build_without_the_value_has_none() {
        assert_eq!(unmask(&[], &[], &[]), None);
        assert_eq!(unmask(&[1, 2], &[1], &[1, 2]), None);
        assert_eq!(unmask(&[0xff], &[0x00], &[0x00]), None); // not UTF-8
    }

    #[test]
    fn equality_needs_the_same_length_and_bytes() {
        assert!(constant_time_eq(b"abc", b"abc"));
        assert!(!constant_time_eq(b"abc", b"abd"));
        assert!(!constant_time_eq(b"abc", b"ab"));
        assert!(constant_time_eq(b"", b""));
    }

    #[test]
    fn the_option_names_match_the_portal_and_the_prompt() {
        assert_eq!(FIXED_OPTION, "dolphin-fixed-password");
        assert_eq!(TECH_ID_OPTION, "dolphin-tech-id");
        assert_eq!(TECH_UNTIL_OPTION, "dolphin-tech-until");
        assert_eq!(PORTAL_DOWN_OPTION, "dolphin-portal-down");
        assert_eq!(CLOCK_SKEW_SECONDS, 600);
        assert!(WAIT_MS >= 6_000 && WAIT_MS % POLL_MS == 0);
    }
}
