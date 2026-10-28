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
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Mutex, Once,
    },
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
/// D19, Sciter: set on the relaunch that «ادامه با همین نسخه» starts; that run skips the update check.
const CONTINUE_ENV: &str = "DOLPHIN_UPDATE_CONTINUE";

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

/// D19: the customer chose to continue with the current version after a failed update. For this process only,
/// never stored: the next start checks again.
static CONTINUE: AtomicBool = AtomicBool::new(false);

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// A folder inside the app's own per-user config directory, never the shared temp folder (review finding d).
fn staging_dir() -> PathBuf {
    Config::path("update")
}

/// False when the config folder is unknown (an empty path would stage in the current folder; review M4).
fn staging_usable() -> bool {
    !staging_dir().as_os_str().is_empty()
}

/// A response is accepted only when it ended on https at the compiled-in portal's host, so a redirect to
/// another host is an error (review M1).
fn from_portal(response: &reqwest::blocking::Response) -> bool {
    let url = response.url();
    let Ok(portal) = url::Url::parse(crate::dolphin::PORTAL_URL) else {
        return false;
    };
    url.scheme() == "https" && url.host_str().is_some() && url.host_str() == portal.host_str()
}

fn phone() -> String {
    rules::pick_phone(&Config::get_option(SUPPORT_PHONE_OPTION), crate::dolphin::SUPPORT_PHONE)
}

/// Asks the portal (at most 4 s) and remembers the answer for the screens.
pub fn check() -> String {
    // Only the first check of the process cleans up: a later one must not delete a running download (review M3).
    static CLEANUP: Once = Once::new();
    CLEANUP.call_once(finish_previous_update);
    let answer = answer();
    *LAST.lock().unwrap() = answer.clone();
    answer.to_string()
}

/// The last `check` answer (the x86 page reads it after its window opens). Only the Sciter (x86) screen uses it.
#[cfg_attr(feature = "flutter", allow(dead_code))]
pub fn last() -> String {
    LAST.lock().unwrap().to_string()
}

/// True when the app must show the update screen instead of opening. False for the rest of the process once the
/// customer chose to continue (D19). Only the Sciter (x86) start-up asks; the Flutter screen decides from `check`.
#[cfg_attr(feature = "flutter", allow(dead_code))]
pub fn blocks_start() -> bool {
    !CONTINUE.load(Ordering::SeqCst) && LAST.lock().unwrap()["state"] != "current"
}

/// D19: «ادامه با همین نسخه». Opens the app at its current version for this run only; nothing is stored.
pub fn continue_current() {
    CONTINUE.store(true, Ordering::SeqCst);
    log::info!("dolphin update: continuing with {}", crate::dolphin::DOLPHIN_VERSION);
}

/// D19, Sciter (x86): the update page cannot turn its own window into the main one, so it starts the same app again
/// with no arguments and `DOLPHIN_UPDATE_CONTINUE=1` (read by `check_blocks_start`) and exits. A portable run starts
/// the customer's packer again (the unpacked copy may be removed when this process ends); an installed run starts
/// its own exe. The packer waits for this process before it unpacks, as after an update.
#[cfg_attr(feature = "flutter", allow(dead_code))]
pub fn continue_in_new_process() {
    continue_current();
    let target = packer_path().filter(|p| p.is_file()).or_else(|| std::env::current_exe().ok());
    let Some(target) = target else {
        log::error!("dolphin update: continue: no exe to start");
        return;
    };
    match std::process::Command::new(&target)
        .env(CONTINUE_ENV, "1")
        .env(WAIT_PID_ENV, std::process::id().to_string())
        .spawn()
    {
        Ok(_) => std::process::exit(0),
        Err(e) => log::error!("dolphin update: continue: start {:?}: {}", target, e),
    }
}

#[cfg_attr(feature = "flutter", allow(dead_code))]
pub fn check_blocks_start() -> bool {
    // The relaunch of «ادامه با همین نسخه»: open the app without asking the portal again.
    if std::env::var(CONTINUE_ENV).map_or(false, |v| v == "1") {
        std::env::remove_var(CONTINUE_ENV); // children (--cm, --connect) do not inherit it
        continue_current();
        return false;
    }
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
    // The strict client probes the portal first (up to ~30 s per probe) before our 4 s GET timeout applies, so the
    // whole check runs on a thread and is given up on after CHECK_TIMEOUT (review I1, D12). A late answer reaches a
    // dropped receiver and changes nothing.
    let (tx, rx) = mpsc::channel();
    let build_owned = build.to_owned();
    std::thread::spawn(move || {
        let result = fetch_offer(portal, &build_owned).map_err(|e| e.to_string());
        tx.send(result).ok();
    });
    let offer = match rx.recv_timeout(CHECK_TIMEOUT) {
        Ok(Ok(Some(offer))) => offer,
        Ok(Ok(None)) => return open,
        Ok(Err(e)) => {
            log::info!("Dolphin update check: {} (opening normally)", e);
            return open;
        }
        Err(_) => {
            log::info!("Dolphin update check: no answer within {:?} (opening normally)", CHECK_TIMEOUT);
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
    if !from_portal(&response) {
        hbb_common::bail!("answer came from another place");
    }
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

/// {"state","percent","text","error"} for the screens; state is idle, downloading, ready, applying or failed.
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
        if p.state == "downloading" || p.state == "ready" || p.state == "applying" {
            return;
        }
        *p = Progress { state: "downloading", received: 0, total: offer.size, reason: "" };
    }
    std::thread::spawn(move || match download(&offer) {
        Ok(()) => PROGRESS.lock().unwrap().state = "ready",
        Err(reason) => {
            log::error!("Dolphin update download failed: {}", reason);
            // D19: a failed try counts like a swapped one, so a broken pin is not downloaded again at every start
            // within the attempt window (Task 8's rule).
            LocalConfig::set_option(ATTEMPT_OPTION.to_owned(), rules::attempt_value(&offer.version, now()));
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
    if !staging_usable() {
        return Err("write");
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
    if !from_portal(&response) || !response.status().is_success() {
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
    let Some(reason) = apply() else {
        return; // another apply is running, or nothing is ready: do nothing
    };
    log::error!("Dolphin update swap failed: {}", reason);
    set_failed(reason);
}

fn apply() -> Option<&'static str> {
    // Only one apply, and only after a finished download (review M2).
    {
        let mut p = PROGRESS.lock().unwrap();
        if p.state != "ready" {
            return None;
        }
        p.state = "applying";
    }
    let Some(offer) = OFFER.lock().unwrap().clone() else {
        return Some("write");
    };
    let Some(staged) = staged_file(&offer).filter(|p| p.is_file()) else {
        return Some("write");
    };
    // Installed path (Windows): keep the staged file open, shared for reading only, from the hash until the process
    // exits, so nobody can write to or replace it while the UAC prompt is up (review I3).
    #[cfg(windows)]
    let held = if crate::platform::is_cur_exe_the_installed() {
        match open_held(&staged) {
            Ok(f) => Some(f),
            Err(_) => return Some("write"),
        }
    } else {
        None
    };
    #[cfg(windows)]
    let hashed = match &held {
        Some(f) => hash_reader(f),
        None => hash_file(&staged),
    };
    #[cfg(not(windows))]
    let hashed = hash_file(&staged);
    // Check the staged file again right before it is used; nothing is swapped unless it still matches.
    if hashed.map_or(true, |(n, h)| rules::verify(&offer, n, &h).is_err()) {
        return Some("hash");
    }
    LocalConfig::set_option(ATTEMPT_OPTION.to_owned(), rules::attempt_value(&offer.version, now()));
    let reason = swap(&staged, &offer);
    #[cfg(windows)]
    drop(held); // reached only when the swap failed; on success the process exits with the handle still open
    Some(reason)
}

/// Opens for reading with FILE_SHARE_READ only: no other handle may write to, truncate, rename or delete the file
/// while we hold it. Running an exe needs read and execute access to it, which this sharing allows, and the
/// packer's payload is `include_bytes!` inside its own mapped image, so it never reopens the file by path.
/// UNVERIFIED until a PC test (acceptance row 46): that the elevated run still starts a file we hold open this way.
/// If it does not, FILE_SHARE_READ | FILE_SHARE_DELETE (3) is the next choice, but it allows renaming.
#[cfg(windows)]
fn open_held(path: &Path) -> std::io::Result<std::fs::File> {
    use std::os::windows::fs::OpenOptionsExt;
    const FILE_SHARE_READ: u32 = 1;
    std::fs::OpenOptions::new().read(true).share_mode(FILE_SHARE_READ).open(path)
}

fn hash_file(path: &Path) -> std::io::Result<(u64, String)> {
    hash_reader(std::fs::File::open(path)?)
}

fn hash_reader(mut file: impl Read) -> std::io::Result<(u64, String)> {
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

