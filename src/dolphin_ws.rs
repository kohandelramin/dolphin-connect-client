//! Dolphin Connect, Plan 18 Phase 6 (DD-42): WebSocket over 443 only when the normal ports fail. The rules are in
//! `src/dolphin_ws_core.rs`; this file holds the one state per process and the small hooks in upstream files:
//!
//! - the customer PC (`src/rendezvous_mediator.rs`): after [`rules::UDP_TIMEOUTS_BEFORE_WS`] UDP registrations
//!   without an answer it restarts its registration over WebSocket ([`udp_timed_out`]); when WebSocket fails too it
//!   goes back to the normal ports ([`mediator_failed`]); under WebSocket, while no session runs, it probes TCP 21116
//!   now and then and returns when it answers ([`start_return_watch`]);
//! - the technician app (`src/client.rs`): when a connection cannot reach hbbs on its normal port it is tried once
//!   more over WebSocket ([`retry_over_ws`]); the following connections start over WebSocket until a background
//!   probe of TCP 21116 answers ([`before_connect`]);
//! - `src/ipc.rs`: the fallback is never told to another process ([`hide_from_ipc`], [`told_option`]), since upstream
//!   stores what it is told and the fallback would become permanent there.
//!
//! Upstream's `allow-websocket` is switched on by adding it to the built-in defaults of this process only
//! (`DEFAULT_SETTINGS`, below anything stored or overridden), so it is never written to a settings file, and an
//! admin's own value of the option always wins.

use crate::dolphin_ws_core as rules;
use hbb_common::{
    config::{Config, DEFAULT_SETTINGS, RENDEZVOUS_PORT},
    log, tokio, ResultType,
};
use std::collections::HashMap;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Mutex, OnceLock,
};
use std::time::Instant;

static STATE: Mutex<rules::Fallback> = Mutex::new(rules::Fallback::new());
/// True while this process has the option in its defaults.
static APPLIED: AtomicBool = AtomicBool::new(false);
/// When a technician connection last failed to reach hbbs on its normal port.
static LAST_UNREACHABLE: Mutex<Option<Instant>> = Mutex::new(None);

fn now_ms() -> u64 {
    static EPOCH: OnceLock<Instant> = OnceLock::new();
    EPOCH.get_or_init(Instant::now).elapsed().as_millis() as u64
}

fn applied() -> bool {
    APPLIED.load(Ordering::SeqCst)
}

/// Whether this process may use the fallback towards `rendezvous_server`.
fn allowed(rendezvous_server: &str) -> bool {
    rules::reaches_443(rendezvous_server, &Config::get_option("api-server"))
        && rules::may_take_over(&Config::get_option(rules::OPTION), applied())
}

/// Turns upstream's WebSocket on or off in this process, then re-tests the NAT type as upstream does whenever the
/// option changes (`CheckTestNatType` in src/common.rs), so a type measured under WebSocket does not stay afterwards.
fn apply(on: bool) {
    {
        let mut defaults = DEFAULT_SETTINGS.write().unwrap();
        if on {
            defaults.insert(rules::OPTION.to_owned(), "Y".to_owned());
            APPLIED.store(true, Ordering::SeqCst);
        } else if APPLIED.swap(false, Ordering::SeqCst) {
            defaults.remove(rules::OPTION);
        }
    }
    crate::test_nat_type();
}

/// A TCP connect to hbbs on its normal port, closed at once. Never over WebSocket (`connect_tcp_local`).
async fn normal_port_answers() -> bool {
    let host = crate::check_port(Config::get_rendezvous_server(), RENDEZVOUS_PORT);
    hbb_common::socket_client::connect_tcp_local(&*host, None, rules::PROBE_TIMEOUT_MS)
        .await
        .is_ok()
}

// ---- the customer PC (src/rendezvous_mediator.rs) ----

/// Hook in `start_udp` after each registration timeout: true when the mediator must restart over WebSocket.
pub fn udp_timed_out(timeouts: i64, host: &str) -> bool {
    if !rules::udp_failed(timeouts) || !allowed(host) {
        return false;
    }
    let retry = {
        let mut st = STATE.lock().unwrap();
        if !st.normal_failed(now_ms()) {
            return false;
        }
        st.retry_after() / 60_000
    };
    log::info!(
        "DD-42: {timeouts} UDP registrations to {host} got no answer, trying WebSocket over 443 (normal port again in {retry} min)"
    );
    apply(true);
    true
}

/// Hook in `start_all` when the mediator ended with an error: under WebSocket, the next try uses the normal ports.
pub fn mediator_failed() {
    if STATE.lock().unwrap().ws_failed() {
        log::info!("DD-42: WebSocket failed too, back to the normal ports");
        apply(false);
    }
}

/// Spawned once by `start_all` on the customer PC. Does nothing until the fallback is on.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn start_return_watch() {
    tokio::spawn(async {
        loop {
            hbb_common::sleep(rules::WATCH_EVERY_MS as f32 / 1000.).await;
            let busy = !crate::server::AUTHED_CONNS.lock().unwrap().is_empty();
            if !STATE.lock().unwrap().probe_due(now_ms(), busy) {
                continue;
            }
            if normal_port_answers().await {
                STATE.lock().unwrap().back_to_normal(now_ms());
                log::info!("DD-42: the normal port answers again, leaving WebSocket");
                apply(false);
                crate::RendezvousMediator::restart();
            } else {
                STATE.lock().unwrap().probe_failed(now_ms());
            }
        }
    });
}

// ---- the technician app (src/client.rs) ----

/// Hook in `_start_inner` on the connect to hbbs (before its `?`): remembers a failure.
pub fn note_connect<T>(res: &ResultType<T>) {
    if res.is_err() {
        *LAST_UNREACHABLE.lock().unwrap() = Some(Instant::now());
    }
}

/// Hook at the start of `Client::start`: under WebSocket, probes the normal port in the background when due, so a
/// later connection goes back to it. The connection being made is not touched. Returns this attempt's start time.
pub fn before_connect() -> Instant {
    let due = {
        let mut st = STATE.lock().unwrap();
        let due = st.probe_due(now_ms(), false);
        if due {
            st.probe_failed(now_ms()); // one probe at a time; a success below returns
        }
        due
    };
    if due {
        tokio::spawn(async {
            if normal_port_answers().await {
                STATE.lock().unwrap().back_to_normal(now_ms());
                log::info!("DD-42: the normal port answers again, the next connection uses it");
                apply(false);
            }
        });
    }
    Instant::now()
}

/// Hook in `Client::start` after a failed attempt that began at `started`: true when it could not reach hbbs on the
/// normal port and is to be tried once more over WebSocket. Under WebSocket a failure turns the fallback off instead.
pub fn retry_over_ws(started: Instant) -> bool {
    let unreachable = LAST_UNREACHABLE.lock().unwrap().map_or(false, |t| t >= started);
    if !unreachable {
        return false;
    }
    let mut st = STATE.lock().unwrap();
    if st.is_on() {
        st.ws_failed();
        drop(st);
        log::info!("DD-42: WebSocket failed too, the next connection uses the normal ports");
        apply(false);
        return false;
    }
    if !allowed(&Config::get_rendezvous_server()) || !st.normal_failed(now_ms()) {
        return false;
    }
    let retry = st.retry_after() / 60_000;
    drop(st);
    log::info!("DD-42: hbbs is not reachable on its normal port, trying WebSocket over 443 (normal port again in {retry} min)");
    apply(true);
    true
}

// ---- src/ipc.rs ----

/// `Data::Options` answer: without the fallback.
pub fn hide_from_ipc(options: &mut HashMap<String, String>) {
    if applied() {
        options.remove(rules::OPTION);
    }
}

/// `Data::SocksWs` answer: the option without the fallback.
pub fn told_option() -> String {
    rules::told_value(&Config::get_option(rules::OPTION), applied()).to_owned()
}
