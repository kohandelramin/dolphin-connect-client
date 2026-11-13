//! Dolphin Connect, Plan 18 Phase 5 (DD-10): the app side of `src/dolphin_wake_core.rs`, which holds the rules and
//! their tests. Here: the adapters (upstream's own `default_net`, which reads `GetAdaptersAddresses` on Windows), the
//! sysinfo fields, the helper's magic packets and the heartbeat field. Hooked in src/hbbs_http/sync.rs, which runs in
//! the server process.

use crate::dolphin_wake_core as rules;
use hbb_common::{config::Config, log};
use serde_json::{json, Value};
use std::sync::Mutex;
use std::time::Instant;

static BOOK: Mutex<rules::WakeBook> = Mutex::new(rules::WakeBook::new());
/// What the last sysinfo said, and when the adapters were last read for it.
static LAST: Mutex<Option<(Vec<String>, Vec<String>, Instant)>> = Mutex::new(None);

/// This PC's adapters. Windows only; elsewhere none (the apps are Windows apps).
fn adapters() -> Vec<rules::Adapter> {
    #[cfg(windows)]
    {
        default_net::get_interfaces()
            .into_iter()
            .map(|i| rules::Adapter {
                if_type: i.if_type.value(),
                description: i.description.unwrap_or_default(),
                mac: i.mac_addr.map(|m| m.octets()),
                ipv4: i.ipv4.iter().map(|n| (n.addr, n.prefix_len)).collect(),
            })
            .collect()
    }
    #[cfg(not(windows))]
    {
        Vec::new()
    }
}

/// Sysinfo (`need_upload` in src/hbbs_http/sync.rs): `dolphin_macs` and `dolphin_lan`, always sent, so the portal can
/// wake this PC through another one later.
pub fn add_sysinfo(v: &mut Value) {
    let list = adapters();
    let macs = rules::report_macs(&list);
    let lan = rules::report_lan(&list);
    v[rules::SYSINFO_MACS] = json!(macs);
    v[rules::SYSINFO_LAN] = json!(lan);
    *LAST.lock().unwrap() = Some((macs, lan, Instant::now()));
}

/// At most every [`rules::LAN_RECHECK_SECS`]: true when the adapters changed since the last sysinfo (a laptop on another
/// network), so the loop sends sysinfo again.
pub fn lan_changed() -> bool {
    let mut last = LAST.lock().unwrap();
    let Some((macs, lan, at)) = last.as_mut() else {
        return false;
    };
    if at.elapsed().as_secs() < rules::LAN_RECHECK_SECS {
        return false;
    }
    *at = Instant::now();
    let list = adapters();
    rules::report_macs(&list) != *macs || rules::report_lan(&list) != *lan
}

#[derive(serde::Deserialize)]
struct Pushed {
    n: String,
    macs: Vec<String>,
    #[serde(default)]
    bcast: Vec<String>,
    until: i64,
}

/// Before each heartbeat (every 15 s, 3 s with a session): a new, valid `dolphin-wake` from the portal sends its packets once, on a
/// thread of its own. Nothing while this PC's `wake-on-lan` switch is hidden (the default).
pub fn tick() {
    let raw = Config::get_option(rules::WAKE_OPTION);
    if raw.is_empty() || raw == "-" {
        return;
    }
    {
        use crate::dolphin_system_core as sys;
        if sys::switch_mode(&Config::get_option(sys::SWITCHES_OPTION), rules::SWITCH_WAKE_ON_LAN) == sys::SwitchMode::Hidden {
            return;
        }
    }
    let Ok(pushed) = serde_json::from_str::<Pushed>(&raw) else {
        return;
    };
    // Taken before it is checked: a bad request is logged once, not every 3 s; a corrected one has a new nonce.
    if !rules::valid_nonce(&pushed.n) || !BOOK.lock().unwrap().take(&pushed.n) {
        return;
    }
    let now = hbb_common::get_time() / 1000;
    let local = rules::local_subnets(&adapters());
    let job = match rules::job(&pushed.n, &pushed.macs, &pushed.bcast, pushed.until, now, &local) {
        Ok(job) => job,
        Err(why) => {
            log::warn!("Wake-on-LAN: request refused ({:?})", why);
            return;
        }
    };
    std::thread::spawn(move || {
        let sent = send(&job);
        log::info!(
            "Wake-on-LAN: {} packets for {} MAC(s) to {} address(es)",
            sent,
            job.macs.len(),
            job.targets.len()
        );
        if sent > 0 {
            BOOK.lock().unwrap().sent(&job.nonce);
        }
    });
}

/// The packets, [`rules::ROUNDS`] times a second apart; the number that left this PC.
fn send(job: &rules::Job) -> usize {
    let sock = match std::net::UdpSocket::bind(("0.0.0.0", 0)) {
        Ok(s) => s,
        Err(e) => {
            log::warn!("Wake-on-LAN: no UDP socket: {}", e);
            return 0;
        }
    };
    if let Err(e) = sock.set_broadcast(true) {
        log::warn!("Wake-on-LAN: broadcast refused: {}", e);
        return 0;
    }
    let mut sent = 0;
    for round in 0..rules::ROUNDS {
        if round > 0 {
            std::thread::sleep(std::time::Duration::from_millis(rules::ROUND_GAP_MS));
        }
        for mac in &job.macs {
            let packet = rules::magic_packet(mac);
            for target in &job.targets {
                if sock.send_to(&packet, (*target, rules::PORT)).is_ok() {
                    sent += 1;
                }
            }
        }
    }
    sent
}

/// The heartbeat's `dolphin_wake`, while one is waiting to be acknowledged.
pub fn heartbeat_report() -> Option<String> {
    BOOK.lock().unwrap().report().map(str::to_owned)
}

/// After the heartbeat: the portal answered one that carried `sent`, so it is not sent again.
pub fn heartbeat_answered(sent: &Option<String>, answered: bool) {
    if let (Some(nonce), true) = (sent, answered) {
        BOOK.lock().unwrap().acknowledged(nonce);
    }
}
