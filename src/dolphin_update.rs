//! Dolphin Connect (TB-20): before the app opens it asks the portal for the newest build of itself. A newer one is
//! downloaded from the portal, checked against the size and SHA-256 the portal gave, swapped in and started; the app
//! does not open until then (owner decision D10). No answer within 4 s, or any error: the app opens (D12).
//! Rules and Persian texts: src/dolphin_update_core.rs. Screens: flutter/lib/dolphin/update*.dart (x64) and
//! src/ui/dolphin_update.html (x86). Nothing is replaced before the new file is verified, and the old portable file
//! is kept as `.old` until the new app has started.
use crate::dolphin_update_core as rules;
use hbb_common::{
    config::{self, Config, LocalConfig},
    log,
};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::Mutex,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const CHECK_TIMEOUT: Duration = Duration::from_secs(4);
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(30 * 60);
const ATTEMPT_OPTION: &str = "dolphin-update-attempt";
/// Pushed by the portal with every heartbeat (app/src/lib/engine/policy.ts SUPPORT_PHONE_OPTION).
const SUPPORT_PHONE_OPTION: &str = "dolphin-support-phone";
/// Set by our packer (libs/portable/src/dolphin_wait.rs).
const PACKER_ENV: &str = "DOLPHIN_PACKER";
const WAIT_PID_ENV: &str = "DOLPHIN_WAIT_PID";

#[derive(Clone)]
struct Progress {
    state: &'static str,
    received: u64,
    total: u64,
    reason: &'static str,
}

lazy_static::lazy_static! {
    static ref LAST: Mutex<Value> = Mutex::new(json!({ "state": "current" }));
    static ref OFFER: Mutex<Option<rules::Offer>> = Mutex::new(None);
    static ref PROGRESS: Mutex<Progress> = Mutex::new(Progress { state: "idle", received: 0, total: 0, reason: "" });
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// A folder inside the app's own per-user config directory, never the shared temp folder (review finding d).
fn staging_dir() -> PathBuf {
    Config::path("update")
}

fn phone() -> String {
    rules::pick_phone(&Config::get_option(SUPPORT_PHONE_OPTION), crate::dolphin::SUPPORT_PHONE)
}

/// Asks the portal (at most 4 s) and remembers the answer for the screens.
pub fn check() -> String {
    finish_previous_update();
    let answer = answer();
    *LAST.lock().unwrap() = answer.clone();
    answer.to_string()
}

/// The last `check` answer (the x86 page reads it after its window opens).
pub fn last() -> String {
    LAST.lock().unwrap().to_string()
}

/// True when the app must show the update screen instead of opening.
pub fn blocks_start() -> bool {
    LAST.lock().unwrap()["state"] != "current"
}

pub fn check_blocks_start() -> bool {
    check();
    blocks_start()
}

fn answer() -> Value {
    let open = json!({ "state": "current" });
    let current = crate::dolphin::DOLPHIN_VERSION;
    let portal = crate::dolphin::PORTAL_URL;
    if !rules::updates_enabled(current, portal) {
        return open;
    }
    let build = rules::build_name(config::is_outgoing_only(), cfg!(target_arch = "x86"));
    let offer = match fetch_offer(portal, build) {
        Ok(Some(offer)) => offer,
        Ok(None) => return open,
        Err(e) => {
            log::info!("Dolphin update check: {} (opening normally)", e);
            return open;
        }
    };
    if !rules::is_newer(current, &offer.version) {
        return open;
    }
    // Never an automatic download for the staff-only technician build or an offer without a portal file (finding b).
    let state = if offer.path.is_none() || config::is_outgoing_only() {
        "manual"
    } else if !rules::may_attempt(&LocalConfig::get_option(ATTEMPT_OPTION), &offer.version, now()) {
        "blocked"
    } else {
        "update"
    };
    let lead = if state == "manual" { rules::manual_text(&offer.version) } else { rules::lead_text(&offer.version) };
    let error = if state == "blocked" { rules::error_text("blocked") } else { "" };
    log::info!("Dolphin update: {} -> {} ({})", current, offer.version, state);
    let version = offer.version.clone();
    *OFFER.lock().unwrap() = Some(offer);
    json!({
        "state": state,
        "version": version,
        "lead": lead,
        "error": error,
        "phone": rules::phone_text(&phone()),
        "downloadPage": format!("{portal}/download"),
    })
}

fn fetch_offer(portal: &str, build: &str) -> hbb_common::ResultType<Option<rules::Offer>> {
    let url = format!("{portal}/api/client/latest?build={build}");
    let client = crate::hbbs_http::create_http_client_with_url_strict(&url)?;
    let response = client.get(&url).timeout(CHECK_TIMEOUT).send()?;
    if response.status().as_u16() == 404 {
        return Ok(None); // nothing pinned yet
    }
    if !response.status().is_success() {
        hbb_common::bail!("HTTP {}", response.status());
    }
    let v: Value = response.json()?;
    let offer = rules::check_offer(
        build,
        v["build"].as_str().unwrap_or(""),
        v["version"].as_str().unwrap_or(""),
        v["sha256"].as_str().unwrap_or(""),
        v["size"].as_u64().unwrap_or(0),
        v["path"].as_str(),
    )
    .map_err(|e| hbb_common::anyhow::anyhow!("portal answer refused: {}", e))?;
    Ok(Some(offer))
}

/// {"state","percent","text","error"} for the screens; state is idle, downloading, ready or failed.
pub fn progress() -> String {
    let p = PROGRESS.lock().unwrap().clone();
    let error = if p.state == "failed" { rules::error_text(p.reason) } else { "" };
    json!({
        "state": p.state,
        "percent": rules::percent(p.received, p.total),
        "text": rules::progress_text(p.received, p.total),
        "error": error,
    })
    .to_string()
}

fn set_failed(reason: &'static str) {
    let mut p = PROGRESS.lock().unwrap();
    p.state = "failed";
    p.reason = reason;
}

/// Starts (or, after a failure, restarts) the download of the offered file. Never touches the running app.
pub fn start_download() {
    let Some(offer) = OFFER.lock().unwrap().clone() else {
        return;
    };
    if offer.path.is_none() || config::is_outgoing_only() {
        return; // manual: nothing is ever downloaded for these
    }
    {
        let mut p = PROGRESS.lock().unwrap();
        if p.state == "downloading" || p.state == "ready" {
            return;
        }
        *p = Progress { state: "downloading", received: 0, total: offer.size, reason: "" };
    }
    std::thread::spawn(move || match download(&offer) {
        Ok(()) => PROGRESS.lock().unwrap().state = "ready",
        Err(reason) => {
            log::error!("Dolphin update download failed: {}", reason);
            set_failed(reason);
        }
    });
}

fn staged_file(offer: &rules::Offer) -> Option<PathBuf> {
    let name = offer.path.as_deref()?.strip_prefix("/download/")?;
    Some(staging_dir().join(name))
}

fn download(offer: &rules::Offer) -> Result<(), &'static str> {
    let path = offer.path.as_deref().ok_or("manual")?;
    if config::is_outgoing_only() {
        return Err("manual");
    }
    let target = staged_file(offer).ok_or("write")?;
    std::fs::create_dir_all(staging_dir()).map_err(|_| "write")?;
    let part = rules::sibling(&target, ".part");
    std::fs::remove_file(&part).ok();
    std::fs::remove_file(&target).ok();
    // Same origin as the check, always: the compiled-in portal plus a path check_offer accepted.
    let url = format!("{}{}", crate::dolphin::PORTAL_URL, path);
    let client = crate::hbbs_http::create_http_client_with_url_strict(&url).map_err(|_| "network")?;
    let mut response = client.get(&url).timeout(DOWNLOAD_TIMEOUT).send().map_err(|_| "network")?;
    if !response.status().is_success() {
        return Err("network");
    }
    if let Err(reason) = write_verified(&mut response, &part, offer) {
        std::fs::remove_file(&part).ok();
        return Err(reason);
    }
    std::fs::rename(&part, &target).map_err(|_| "write")
}

fn write_verified(body: &mut impl Read, part: &Path, offer: &rules::Offer) -> Result<(), &'static str> {
    let mut file = std::fs::File::create(part).map_err(|_| "write")?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 64 * 1024];
    let mut received = 0u64;
    loop {
        let n = body.read(&mut buf).map_err(|_| "network")?;
        if n == 0 {
            break;
        }
        received += n as u64;
        if received > offer.size {
            return Err("size");
        }
        hasher.update(&buf[..n]);
        file.write_all(&buf[..n]).map_err(|_| "write")?;
        PROGRESS.lock().unwrap().received = received;
    }
    file.sync_all().map_err(|_| "write")?;
    rules::verify(offer, received, &rules::hex(&hasher.finalize()))
}

/// Swaps the verified file in and starts it. Returns only on failure, which the screens then show.
pub fn apply_or_fail() {
    let reason = apply();
    log::error!("Dolphin update swap failed: {}", reason);
    set_failed(reason);
}

fn apply() -> &'static str {
    let Some(offer) = OFFER.lock().unwrap().clone() else {
        return "write";
    };
    let Some(staged) = staged_file(&offer).filter(|p| p.is_file()) else {
        return "write";
    };
    // Check the staged file again right before it is used; nothing is swapped unless it still matches.
    if hash_file(&staged).map_or(true, |(n, h)| rules::verify(&offer, n, &h).is_err()) {
        return "hash";
    }
    LocalConfig::set_option(ATTEMPT_OPTION.to_owned(), rules::attempt_value(&offer.version, now()));
    swap(&staged, &offer)
}

fn hash_file(path: &Path) -> std::io::Result<(u64, String)> {
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 64 * 1024];
    let mut total = 0u64;
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        total += n as u64;
        hasher.update(&buf[..n]);
    }
    Ok((total, rules::hex(&hasher.finalize())))
}

#[cfg(windows)]
fn swap(staged: &Path, offer: &rules::Offer) -> &'static str {
    if crate::platform::is_cur_exe_the_installed() {
        // UNVERIFIED (acceptance row 46): upstream's own installed-app update. The new exe runs `--update` with UAC
        // and copies itself over the installed one (src/platform/windows.rs update_me), restarting the service.
        return match crate::platform::update_to(&staged.to_string_lossy()) {
            Ok(()) => std::process::exit(0),
            Err(e) => {
                log::error!("update_to: {}", e);
                "elevation"
            }
        };
    }
    // Portable (UNVERIFIED, acceptance row 45): replace the file the customer started; keep it as `.old` until the
    // new app runs (check() deletes it then). The new packer waits for this process before it unpacks.
    let Some(packer) = packer_path().filter(|p| p.is_file()) else {
        return "packer";
    };
    let new = rules::sibling(&packer, ".new");
    let old = rules::sibling(&packer, ".old");
    std::fs::remove_file(&new).ok();
    let copied = std::fs::copy(staged, &new).is_ok();
    // The copy next to the customer's file is checked too, before anything is renamed.
    if !copied || hash_file(&new).map_or(true, |(n, h)| rules::verify(offer, n, &h).is_err()) {
        std::fs::remove_file(&new).ok();
        return "write";
    }
    std::fs::remove_file(&old).ok();
    if std::fs::rename(&packer, &old).is_err() {
        std::fs::remove_file(&new).ok();
        return "write";
    }
    if std::fs::rename(&new, &packer).is_err() {
        std::fs::rename(&old, &packer).ok();
        return "write";
    }
    match std::process::Command::new(&packer).env(WAIT_PID_ENV, std::process::id().to_string()).spawn() {
        Ok(_) => {
            std::fs::remove_file(staged).ok();
            std::process::exit(0)
        }
        Err(e) => {
            log::error!("start {:?}: {}", packer, e);
            // Put the customer's file back as it was.
            std::fs::rename(&packer, &new).ok();
            std::fs::rename(&old, &packer).ok();
            std::fs::remove_file(&new).ok();
            "start"
        }
    }
}

#[cfg(not(windows))]
fn swap(_staged: &Path, _offer: &rules::Offer) -> &'static str {
    "packer"
}

/// The new app has started: the old portable file and the downloaded copy are no longer needed.
fn finish_previous_update() {
    if let Some(packer) = packer_path() {
        std::fs::remove_file(rules::sibling(&packer, ".old")).ok();
    }
    std::fs::remove_dir_all(staging_dir()).ok();
}

/// `DOLPHIN_PACKER`, with an empty value treated as absent (finding c).
fn packer_path() -> Option<PathBuf> {
    std::env::var_os(PACKER_ENV).filter(|v| !v.is_empty()).map(PathBuf::from)
}

