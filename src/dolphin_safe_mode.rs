//! Dolphin Connect, Plan 18 Phase 5 (DD-11): the app side of `src/dolphin_safe_mode_core.rs`, which holds the rules,
//! the texts, the command lines and their tests. Here: the messages, the Windows steps (registry with `winreg`,
//! `bcdedit` by full path, the restart with `system_shutdown` as upstream's own restart does) and the two ways a request
//! reaches the privileged server process:
//!
//! - the technician's request arrives at `Connection` (src/server/connection.rs), which runs in the server process.
//!   An installed app's server is started by its Windows service with the SYSTEM token
//!   (`platform::windows::launch_privileged_process`), so it may write HKLM and run bcdedit itself;
//! - the customer's own «بازگشت به حالت عادی» comes from the main window (run as the user) over the existing IPC
//!   options message ([`ask_return`] → [`ipc_take_return`] in src/ipc.rs).
//!
//! Booted in Safe Mode, the service removes the safeboot value as it starts ([`on_service_start`], hooked in
//! `run_service`), before anyone signs in, so the following restart is normal whatever happens.

use crate::dolphin_safe_mode_core as rules;
use base::message_proto::*;
use hbb_common::{config::Config, log};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};

/// A restart is being prepared or Windows is going down; any other request is refused.
static RESTARTING: AtomicBool = AtomicBool::new(false);

pub fn busy() -> bool {
    RESTARTING.load(Ordering::SeqCst)
}

/// Customer's PC: the answer, an existing `MessageBox` the Dolphin technician app shows in its own dialog.
pub fn answer_message(answer: rules::Answer) -> Message {
    let mut msg = Message::new();
    msg.set_message_box(MessageBox {
        msgtype: rules::ANSWER_MSGTYPE.to_owned(),
        title: answer.code().to_owned(),
        text: answer.text(),
        link: "".to_owned(),
        ..Default::default()
    });
    msg
}

/// Whether Windows runs in Safe Mode now.
pub fn in_safe_mode() -> bool {
    rules::in_safe_mode(clean_boot())
}

/// The organization's `safe-mode` switch (DD-4) is hidden: the default.
pub fn switch_hidden() -> bool {
    use crate::dolphin_system_core as sys;
    sys::switch_mode(&Config::get_option(sys::SWITCHES_OPTION), rules::SWITCH_SAFE_MODE) == sys::SwitchMode::Hidden
}

pub fn installed() -> bool {
    #[cfg(windows)]
    {
        crate::platform::is_installed()
    }
    #[cfg(not(windows))]
    {
        false
    }
}

/// The server runs as SYSTEM (an installed app's service started it).
pub fn privileged() -> bool {
    #[cfg(windows)]
    {
        crate::platform::is_root()
    }
    #[cfg(not(windows))]
    {
        false
    }
}

/// Told to the technician at login (`platform_additions`): this PC takes «ری‌استارت در حالت امن».
pub fn offered() -> bool {
    rules::offered(cfg!(feature = "flutter"), switch_hidden(), installed(), privileged(), in_safe_mode())
}

fn clean_boot() -> i32 {
    #[cfg(windows)]
    {
        win::clean_boot()
    }
    #[cfg(not(windows))]
    {
        0
    }
}

/// Blocking (registry and bcdedit, well under a second): the steps before the restart. A failed step undoes the ones
/// before it. Marks the PC busy; [`reboot_later`] or a failure clears it.
pub fn prepare(kind: rules::Kind) -> Result<(), rules::Step> {
    if RESTARTING.swap(true, Ordering::SeqCst) {
        return Err(rules::Step::Register);
    }
    #[cfg(windows)]
    let result = win::prepare(kind);
    #[cfg(not(windows))]
    let result = {
        let _ = kind;
        Err(rules::Step::Register)
    };
    if result.is_err() {
        RESTARTING.store(false, Ordering::SeqCst);
    }
    result
}

/// After [`prepare`] and the audit: give the audit post [`rules::AUDIT_DELAY_MS`], then restart Windows. If Windows
/// refuses, the prepared steps are undone and `failed` runs (on this thread).
pub fn reboot_later(kind: rules::Kind, failed: impl FnOnce(rules::Step) + Send + 'static) {
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(rules::AUDIT_DELAY_MS));
        #[cfg(windows)]
        let ok = win::reboot(kind);
        #[cfg(not(windows))]
        let ok = {
            let _ = kind;
            false
        };
        if !ok {
            RESTARTING.store(false, Ordering::SeqCst);
            failed(rules::Step::Restart);
        }
    });
}

/// Service start (`run_service`): in Safe Mode remove the safeboot value at once; after a normal boot remove what a
/// Safe Mode restart left (the `SafeBoot\Network` entry, the RunOnce value). Off the service's own thread.
pub fn on_service_start() {
    #[cfg(windows)]
    std::thread::spawn(|| win::at_service_start());
}

// ---- the customer's own «بازگشت به حالت عادی» ----

/// Main window (as the user): ask the server process over the IPC. The answer is [`rules::ReturnAnswer::code`], or
/// "no-service" when no server of this build answered. The request rides on the IPC options message with the
/// server's own options read first, so a server that does not know the key (another build) only stores it.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn ask_return() -> String {
    ask_service(hbb_common::get_time() / 1000).unwrap_or_else(|| "no-service".to_owned())
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[hbb_common::tokio::main(flavor = "current_thread", crate = "hbb_common::tokio")]
async fn ask_service(now_secs: i64) -> Option<String> {
    let mut options = crate::ipc::get_options_async().await;
    options.insert(rules::RETURN_OPTION.to_owned(), now_secs.to_string());
    let mut c = crate::ipc::connect(1000, "").await.ok()?;
    c.send(&crate::ipc::Data::Options(Some(options))).await.ok()?;
    match c.next_timeout(3000).await {
        Ok(Some(crate::ipc::Data::Options(Some(answer)))) => answer.get(rules::RETURN_OPTION).cloned(),
        _ => None,
    }
}

/// Server process (src/ipc.rs, `Data::Options`): takes the request out of the options before they are stored and
/// answers it; `None` when there was none (upstream answers as before).
pub fn ipc_take_return(options: &mut HashMap<String, String>) -> Option<HashMap<String, String>> {
    static LAST: std::sync::Mutex<Option<i64>> = std::sync::Mutex::new(None);
    let raw = options.remove(rules::RETURN_OPTION)?;
    let now = hbb_common::get_time() / 1000;
    let mut last = LAST.lock().unwrap();
    let answer = rules::return_answer(&raw, now, *last, in_safe_mode(), busy());
    log::info!("Safe Mode: the customer asked for a normal restart: {}", answer.code());
    if answer == rules::ReturnAnswer::Restarting {
        *last = raw.trim().parse().ok();
        std::thread::spawn(|| {
            if let Err(step) = prepare(rules::Kind::Normal) {
                log::error!("Safe Mode: the normal restart failed at {:?}", step);
                return;
            }
            post_return_audit();
            reboot_later(rules::Kind::Normal, |step| {
                log::error!("Safe Mode: the normal restart failed at {:?}", step)
            });
        });
    }
    let mut reply = HashMap::new();
    reply.insert(rules::RETURN_OPTION.to_owned(), answer.code().to_owned());
    Some(reply)
}

/// The customer's return has no connection of its own: the connection audit's `normal_restart` goes out once, on an
/// open connection of this server if there is one, else with `conn_id` 0 (the portal audits a restart whether or not
/// the connection is open). The same fields as `Connection::post_conn_audit`, without the session.
fn post_return_audit() {
    let url = crate::get_audit_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
        "conn".to_owned(),
    );
    if url.is_empty() {
        return;
    }
    let conn_id = crate::Connection::alive_conns().first().copied().unwrap_or(0);
    let v = serde_json::json!({
        "action": rules::AUDIT_NORMAL_RESTART,
        "id": Config::get_id(),
        "uuid": crate::encode64(hbb_common::get_uuid()),
        "conn_id": conn_id,
        "nonce": uuid::Uuid::new_v4().to_string(),
    });
    if let Err(e) = crate::post_request_sync(url, v.to_string(), "") {
        log::warn!("Safe Mode: the normal_restart audit was not posted: {}", e);
    }
}

#[cfg(windows)]
mod win {
    use super::rules::{self, BootStep, Kind, Step};
    use hbb_common::log;
    use std::os::windows::process::CommandExt;
    use winreg::{enums::*, RegKey};

    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    /// `GetSystemMetrics(SM_CLEANBOOT)`; the registry's `SafeBoot\Option\OptionValue`, which exists only in a Safe
    /// Mode boot, when the call says 0 (a service has no desktop of its own).
    pub fn clean_boot() -> i32 {
        let metric = unsafe { winapi::um::winuser::GetSystemMetrics(winapi::um::winuser::SM_CLEANBOOT) };
        if metric != 0 {
            return metric;
        }
        RegKey::predef(HKEY_LOCAL_MACHINE)
            .open_subkey(rules::SAFEBOOT_OPTION)
            .and_then(|k| k.get_value::<u32, _>("OptionValue"))
            .map(|v| v as i32)
            .unwrap_or(0)
    }

    fn bcdedit(args: &[&str]) -> bool {
        let exe = rules::bcdedit_path(&std::env::var("SystemRoot").unwrap_or_default());
        match std::process::Command::new(&exe).args(args).creation_flags(CREATE_NO_WINDOW).output() {
            Ok(out) => {
                if !out.status.success() {
                    log::warn!("Safe Mode: bcdedit {} ended with {:?}", args.join(" "), out.status.code());
                }
                out.status.success()
            }
            Err(e) => {
                log::error!("Safe Mode: bcdedit did not start: {}", e);
                false
            }
        }
    }

    fn service_key() -> Option<String> {
        rules::safeboot_key(&crate::get_app_name())
    }

    /// `SafeBoot\Network\<service>` = "Service": the service starts in Safe Mode with networking.
    fn register() -> bool {
        let Some(path) = service_key() else {
            return false;
        };
        match RegKey::predef(HKEY_LOCAL_MACHINE).create_subkey(&path) {
            Ok((key, _)) => key.set_value("", &rules::SAFEBOOT_VALUE).is_ok(),
            Err(e) => {
                log::error!("Safe Mode: {} not written: {}", path, e);
                false
            }
        }
    }

    /// Only our own key, never one with subkeys (`RegDeleteKey`, not a tree delete).
    fn unregister() {
        if let Some(path) = service_key() {
            let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
            if hklm.open_subkey(&path).is_ok() {
                if let Err(e) = hklm.delete_subkey(&path) {
                    log::warn!("Safe Mode: {} not removed: {}", path, e);
                }
            }
        }
    }

    fn runonce_set() -> bool {
        let Ok(exe) = std::env::current_exe() else {
            return false;
        };
        let name = rules::runonce_name(&crate::get_app_name());
        let command = rules::runonce_command(&exe.to_string_lossy());
        match RegKey::predef(HKEY_LOCAL_MACHINE).create_subkey(rules::RUNONCE_KEY) {
            Ok((key, _)) => key.set_value(&name, &command).is_ok(),
            Err(e) => {
                log::error!("Safe Mode: RunOnce not written: {}", e);
                false
            }
        }
    }

    fn runonce_remove() {
        let name = rules::runonce_name(&crate::get_app_name());
        if let Ok(key) = RegKey::predef(HKEY_LOCAL_MACHINE).open_subkey_with_flags(rules::RUNONCE_KEY, KEY_ALL_ACCESS) {
            if key.get_raw_value(&name).is_ok() {
                key.delete_value(&name).ok();
            }
        }
    }

    pub fn prepare(kind: Kind) -> Result<(), Step> {
        match kind {
            Kind::Safe => {
                if !register() {
                    unregister();
                    return Err(Step::Register);
                }
                if !bcdedit(&rules::bcdedit_set_args()) {
                    unregister();
                    return Err(Step::Bcdedit);
                }
                if !runonce_set() {
                    bcdedit(&rules::bcdedit_delete_args());
                    unregister();
                    return Err(Step::RunOnce);
                }
            }
            Kind::Normal => {
                // Removed at boot already (at_service_start); again here in case that failed. An error is expected
                // when the value is gone.
                bcdedit(&rules::bcdedit_delete_args());
                unregister();
            }
        }
        log::info!("Safe Mode: prepared the {} restart", kind.code());
        Ok(())
    }

    /// Upstream's own restart call (`Misc::RestartRemoteDevice`): `ExitWindowsEx` with force.
    pub fn reboot(kind: Kind) -> bool {
        match system_shutdown::force_reboot() {
            Ok(_) => {
                log::info!("Safe Mode: Windows restarts ({})", kind.code());
                true
            }
            Err(e) => {
                log::error!("Safe Mode: Windows did not restart: {}", e);
                if kind == Kind::Safe {
                    bcdedit(&rules::bcdedit_delete_args());
                    runonce_remove();
                    unregister();
                }
                false
            }
        }
    }

    pub fn at_service_start() {
        match rules::at_service_start(clean_boot()) {
            BootStep::RemoveSafeboot => {
                let ok = bcdedit(&rules::bcdedit_delete_args());
                log::info!("Safe Mode: booted in Safe Mode; safeboot value removed: {}", ok);
            }
            BootStep::CleanLeftovers => {
                unregister();
                runonce_remove();
            }
        }
    }
}
