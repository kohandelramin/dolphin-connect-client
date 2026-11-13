//! Dolphin Connect, Plan 18 Phase 6 (DD-42, owner 2026-11-13: "yes, prepare it"): the rules for WebSocket over port
//! 443, used only when the normal ports (TCP 21115-21117, UDP 21116) fail. Standard library only, so CI tests it alone
//! (`rustc --edition 2021 --test src/dolphin_ws_core.rs`); `src/dolphin_ws.rs` wires it into the app.
//!
//! The transport is upstream's own: with the option `allow-websocket` on, libs/hbb_common (unchanged) turns
//! `remote.dolphindev.ir:21116` into `wss://remote.dolphindev.ir/ws/id` and `:21117` into `.../ws/relay`
//! (`websocket::check_ws`), registers over TCP instead of UDP and relays every session. Upstream reads that option as a
//! permanent setting; here it is switched on in memory only, by the rules below, and never stored or told to another
//! process. A working connection is never moved: the switch only decides how the next connection starts.

/// Upstream's option (libs/hbb_common config `keys::OPTION_ALLOW_WEBSOCKET`).
pub const OPTION: &str = "allow-websocket";

/// UDP registrations in a row without hbbs's answer before the customer PC tries WebSocket. Upstream waits 3 s for
/// each (`MIN_REG_TIMEOUT` in src/rendezvous_mediator.rs) and keeps sending forever, so the PC would otherwise stay
/// offline on a network that blocks UDP 21116: four make about 12 seconds.
pub const UDP_TIMEOUTS_BEFORE_WS: i64 = 4;

/// How long WebSocket is kept before the normal port is tried again, at first.
pub const RETRY_NORMAL_MIN_MS: u64 = 10 * 60 * 1000;
/// The longest wait, reached by doubling when the normal ports keep failing soon after each return.
pub const RETRY_NORMAL_MAX_MS: u64 = 6 * 60 * 60 * 1000;
/// A normal-port failure this soon after a return counts as the same blocked network (the wait doubles).
pub const RELAPSE_MS: u64 = 2 * 60 * 1000;
/// The probe of the normal port (a TCP connect to hbbs on 21116, closed at once).
pub const PROBE_TIMEOUT_MS: u64 = 3000;
/// How often the customer PC looks whether a probe is due.
pub const WATCH_EVERY_MS: u64 = 30 * 1000;

/// Whether upstream's mapping lands on 443 with TLS. The rendezvous server must be a name: an IP maps to
/// `ws://<ip>:21118`, a port the same networks block. The API server must be https: upstream picks `wss` from it and,
/// under WebSocket, skips its own key exchange with hbbs, so plain `ws://` would carry the signalling in the clear.
pub fn reaches_443(rendezvous_server: &str, api_server: &str) -> bool {
    let host = host_of(rendezvous_server);
    !host.is_empty() && !is_ip(host) && api_server.starts_with("https://")
}

/// `host` from `host`, `host:port`, `[v6]:port` or a bare v6 address.
fn host_of(server: &str) -> &str {
    let s = server.trim();
    if let Some(rest) = s.strip_prefix('[') {
        return rest.split(']').next().unwrap_or("");
    }
    if s.matches(':').count() > 1 {
        return s; // a bare IPv6 address
    }
    s.split(':').next().unwrap_or("")
}

fn is_ip(host: &str) -> bool {
    host.parse::<std::net::IpAddr>().is_ok()
}

/// The fallback may take the option only while nobody set it: an admin's own `allow-websocket` (stored, overridden
/// or built in) is upstream's permanent WebSocket, and the fallback leaves it alone.
pub fn may_take_over(current_value: &str, applied_by_us: bool) -> bool {
    applied_by_us || current_value.is_empty()
}

/// The customer PC's UDP registration failed often enough to try WebSocket.
pub fn udp_failed(timeouts: i64) -> bool {
    timeouts >= UDP_TIMEOUTS_BEFORE_WS
}

/// What another process is told about the option over the IPC (`Data::Options`, `Data::SocksWs`): the value without
/// the fallback. Upstream copies what it is told into that process's stored settings, which would make the fallback
/// permanent there.
pub fn told_value<'a>(current_value: &'a str, applied_by_us: bool) -> &'a str {
    if applied_by_us {
        ""
    } else {
        current_value
    }
}

/// The fallback's state in one process (the customer's service, or the technician app). Times are milliseconds on a
/// monotonic clock.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Fallback {
    on: bool,
    on_since: u64,
    retry_after: u64,
    last_return: Option<u64>,
}

impl Fallback {
    pub const fn new() -> Self {
        Self { on: false, on_since: 0, retry_after: RETRY_NORMAL_MIN_MS, last_return: None }
    }

    pub fn is_on(&self) -> bool {
        self.on
    }

    pub fn retry_after(&self) -> u64 {
        self.retry_after
    }

    /// The normal ports failed. True when this turns WebSocket on (false when it already was).
    pub fn normal_failed(&mut self, now: u64) -> bool {
        if self.on {
            return false;
        }
        self.retry_after = match self.last_return {
            Some(t) if now.saturating_sub(t) < RELAPSE_MS => {
                self.retry_after.saturating_mul(2).clamp(RETRY_NORMAL_MIN_MS, RETRY_NORMAL_MAX_MS)
            }
            _ => RETRY_NORMAL_MIN_MS,
        };
        self.on = true;
        self.on_since = now;
        true
    }

    /// WebSocket failed too: the next attempt uses the normal ports again. True when this turns WebSocket off.
    pub fn ws_failed(&mut self) -> bool {
        let was = self.on;
        self.on = false;
        self.last_return = None;
        was
    }

    /// Whether to probe the normal port now: under WebSocket, after the wait, and on the customer PC never while a
    /// session runs (`busy`), since a return restarts its registration with hbbs.
    pub fn probe_due(&self, now: u64, busy: bool) -> bool {
        self.on && !busy && now.saturating_sub(self.on_since) >= self.retry_after
    }

    /// The probe reached the normal port: the next attempt uses it.
    pub fn back_to_normal(&mut self, now: u64) {
        self.on = false;
        self.last_return = Some(now);
    }

    /// The probe failed: wait the same time again.
    pub fn probe_failed(&mut self, now: u64) {
        self.on_since = now;
    }
}

impl Default for Fallback {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const API: &str = "https://support.dolphindev.ir/rd";

    #[test]
    fn only_a_server_name_with_an_https_api_server_reaches_443() {
        assert!(reaches_443("remote.dolphindev.ir", API));
        assert!(reaches_443("remote.dolphindev.ir:21116", API));
        assert!(!reaches_443("remote.dolphindev.ir", "http://support.dolphindev.ir/rd")); // ws:// in the clear
        assert!(!reaches_443("remote.dolphindev.ir", ""));
        assert!(!reaches_443("185.1.2.3", API)); // ws://185.1.2.3:21118
        assert!(!reaches_443("185.1.2.3:21116", API));
        assert!(!reaches_443("[2a01::1]:21116", API));
        assert!(!reaches_443("2a01::1", API));
        assert!(!reaches_443("", API));
        assert!(!reaches_443("  ", API));
    }

    #[test]
    fn an_admins_own_websocket_setting_is_left_alone() {
        assert!(may_take_over("", false));
        assert!(may_take_over("Y", true)); // ours
        assert!(!may_take_over("Y", false));
        assert!(!may_take_over("N", false));
        assert_eq!(told_value("Y", true), "");
        assert_eq!(told_value("Y", false), "Y");
        assert_eq!(told_value("", false), "");
    }

    #[test]
    fn four_lost_udp_registrations_try_websocket() {
        assert!(!udp_failed(0));
        assert!(!udp_failed(3));
        assert!(udp_failed(4));
        assert!(udp_failed(40));
    }

    #[test]
    fn websocket_stays_until_it_fails_or_the_normal_port_answers() {
        let mut f = Fallback::new();
        assert!(!f.is_on());
        assert!(!f.probe_due(u64::MAX, false)); // nothing to probe on the normal path
        assert!(f.normal_failed(1_000));
        assert!(f.is_on());
        assert!(!f.normal_failed(2_000)); // already on
        assert!(!f.probe_due(1_000 + RETRY_NORMAL_MIN_MS - 1, false));
        assert!(f.probe_due(1_000 + RETRY_NORMAL_MIN_MS, false));
        assert!(!f.probe_due(1_000 + RETRY_NORMAL_MIN_MS, true)); // never during a session
        f.probe_failed(1_000 + RETRY_NORMAL_MIN_MS);
        assert!(f.is_on());
        assert!(!f.probe_due(1_000 + RETRY_NORMAL_MIN_MS + 1, false));
        assert!(f.ws_failed());
        assert!(!f.is_on());
        assert!(!f.ws_failed());
    }

    #[test]
    fn a_return_that_fails_at_once_doubles_the_wait_up_to_six_hours() {
        let mut f = Fallback::new();
        let mut now = 0;
        f.normal_failed(now);
        let mut expected = RETRY_NORMAL_MIN_MS;
        for _ in 0..12 {
            assert_eq!(f.retry_after(), expected);
            now += f.retry_after();
            assert!(f.probe_due(now, false));
            f.back_to_normal(now);
            assert!(!f.is_on());
            now += RELAPSE_MS - 1; // the normal ports fail again soon
            assert!(f.normal_failed(now));
            expected = (expected * 2).min(RETRY_NORMAL_MAX_MS);
        }
        assert_eq!(f.retry_after(), RETRY_NORMAL_MAX_MS);
        // a return that holds resets the wait
        now += f.retry_after();
        f.back_to_normal(now);
        assert!(f.normal_failed(now + RELAPSE_MS));
        assert_eq!(f.retry_after(), RETRY_NORMAL_MIN_MS);
        // and a WebSocket failure forgets the last return
        f.ws_failed();
        assert!(f.normal_failed(now + RELAPSE_MS + 1));
        assert_eq!(f.retry_after(), RETRY_NORMAL_MIN_MS);
    }
}
