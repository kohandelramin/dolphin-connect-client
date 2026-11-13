//! Dolphin Connect, Plan 18 Phase 5 (DD-11): restart a customer's PC into Safe Mode with networking, and back. The
//! rules, the texts and the exact Windows command lines, standard library only, so CI tests them alone
//! (`rustc --edition 2021 --test src/dolphin_safe_mode_core.rs`). The app side is src/dolphin_safe_mode.rs; the hooks
//! are in src/server/connection.rs, src/ui_session_interface.rs, src/flutter_ffi.rs, src/ui_cm_interface.rs, src/ipc.rs
//! and src/platform/windows.rs (`run_service`), each marked `Dolphin Connect (DD-11)`.
//!
//! Never upstream's remote restart: `enable-remote-restart` stays "N" and `Misc::RestartRemoteDevice` is untouched. The
//! technician's app asks with the existing `Misc::PluginRequest` ([`REQUEST_ID`], as the side pane's paste does); an
//! older customer app drops it unread. The answer is the existing `MessageBox` with [`ANSWER_MSGTYPE`].
//!
//! Consent (ADR-0015, ADR-0016) is unchanged: the customer sees [`NOTICE_SECS`] seconds of notice with «لغو» first;
//! after the restart a connection still needs the window open (the RunOnce entry opens it after sign-in) and the
//! portal's authorization. Nothing here accepts a connection.

/// `PluginRequest.id` of the request; the content is [`Kind::code`].
pub const REQUEST_ID: &str = "dolphin-safe-mode";
/// `MessageBox.msgtype` of every answer; `title` is [`Answer::code`], `text` the Persian line.
pub const ANSWER_MSGTYPE: &str = "dolphin-safe-mode";
/// The portal's feature switch (DD-4); hidden by default, like every key the app does not list.
pub const SWITCH_SAFE_MODE: &str = "safe-mode";
/// The customer's notice before Windows restarts.
pub const NOTICE_SECS: u64 = 20;
/// `platform_additions` key of the login answer: true while the customer's PC runs in Safe Mode, so the technician's
/// toolbar offers «بازگشت به حالت عادی».
pub const PLATFORM_ADDITION: &str = "dolphin_safe_mode";

/// `platform_additions` key of the login answer: true when this PC would take «ری‌استارت در حالت امن» ([`offered`]).
/// The technician app has no heartbeat (an outgoing-only app never starts it), so it never knows the organization's
/// switches itself: its toolbar shows the entry only when the customer's PC says so here.
pub const PLATFORM_OFFERED: &str = "dolphin_safe_mode_offered";

/// Connection → customer window (`ipc::Data::SwitchPermission` names): show (`true`) or hide the notice.
pub const CM_NOTICE_SAFE: &str = "dolphin-restart-safe";
pub const CM_NOTICE_NORMAL: &str = "dolphin-restart-normal";
/// Customer window → connection: «لغو».
pub const CM_CANCEL: &str = "dolphin-restart-cancel";

/// The customer's own «بازگشت به حالت عادی» from the main window: a lone option sent over the IPC to the server
/// process, whose value is the request's unix time. Never stored.
pub const RETURN_OPTION: &str = "dolphin-normal-restart";
/// How old a return request may be (seconds), so a stale one never restarts a PC.
pub const RETURN_FRESH_SECS: i64 = 60;

/// The connection audit's `action` (contract 2026-11-13; the portal audits engine.safe_mode_restart and
/// engine.normal_restart).
pub const AUDIT_SAFE_MODE: &str = "safe_mode";
pub const AUDIT_NORMAL_RESTART: &str = "normal_restart";
/// Time the audit post gets before Windows goes down.
pub const AUDIT_DELAY_MS: u64 = 2500;

/// Where a service is allowed to start in Safe Mode with networking.
pub const SAFEBOOT_NETWORK: &str = r"SYSTEM\CurrentControlSet\Control\SafeBoot\Network";
/// The default value of a service's key there.
pub const SAFEBOOT_VALUE: &str = "Service";
/// Exists only in a Safe Mode boot; `OptionValue` is 1 (minimal) or 2 (networking).
pub const SAFEBOOT_OPTION: &str = r"SYSTEM\CurrentControlSet\Control\SafeBoot\Option";
/// HKLM; runs once at the next sign-in, then Windows deletes the value.
pub const RUNONCE_KEY: &str = r"SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";

/// Which restart.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// Into Safe Mode with networking.
    Safe,
    /// Back to normal from Safe Mode.
    Normal,
}

impl Kind {
    pub fn parse(code: &str) -> Option<Kind> {
        match code {
            "safe" => Some(Kind::Safe),
            "normal" => Some(Kind::Normal),
            _ => None,
        }
    }

    pub fn code(self) -> &'static str {
        match self {
            Kind::Safe => "safe",
            Kind::Normal => "normal",
        }
    }

    pub fn audit_action(self) -> &'static str {
        match self {
            Kind::Safe => AUDIT_SAFE_MODE,
            Kind::Normal => AUDIT_NORMAL_RESTART,
        }
    }

    pub fn cm_notice(self) -> &'static str {
        match self {
            Kind::Safe => CM_NOTICE_SAFE,
            Kind::Normal => CM_NOTICE_NORMAL,
        }
    }

    /// The customer window's notice for a `SwitchPermission` name.
    pub fn from_cm_notice(name: &str) -> Option<Kind> {
        match name {
            CM_NOTICE_SAFE => Some(Kind::Safe),
            CM_NOTICE_NORMAL => Some(Kind::Normal),
            _ => None,
        }
    }
}

/// Technician's app (`session_set_common` key and value): the `PluginRequest` to send, or `None` when the key is not
/// ours or the value is bad (nothing is sent).
pub fn client_request(key: &str, value: &str) -> Option<(&'static str, Vec<u8>)> {
    if key != REQUEST_ID {
        return None;
    }
    Kind::parse(value).map(|k| (REQUEST_ID, k.code().as_bytes().to_vec()))
}

/// Customer's PC: the request in a `PluginRequest`, or `None` for anything else.
pub fn request(id: &str, content: &[u8]) -> Option<Kind> {
    if id != REQUEST_ID {
        return None;
    }
    Kind::parse(std::str::from_utf8(content).ok()?)
}

/// Whether a `PluginRequest` id is this request (the pause gate treats it as control, not as typing).
pub fn is_request(id: &str) -> bool {
    id == REQUEST_ID
}

/// What the customer's PC knows when a request comes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Scene {
    /// The customer window can show the notice (the Flutter build; the x86 Sciter window cannot).
    pub ui: bool,
    /// The organization's `safe-mode` switch is hidden.
    pub switch_hidden: bool,
    /// The app is installed (a portable run has no service to come back with).
    pub installed: bool,
    /// The server runs as SYSTEM (the installed service), so it may write HKLM and run bcdedit.
    pub privileged: bool,
    /// Windows runs in Safe Mode now.
    pub in_safe_mode: bool,
    /// The customer paused the session (DD-46): no control from the technician.
    pub paused: bool,
    /// A restart is counting down or under way.
    pub busy: bool,
    /// The customer window has this session, so the notice can show.
    pub window: bool,
}

/// Why the customer's PC said no.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refusal {
    Unsupported,
    SwitchHidden,
    Portable,
    NoService,
    AlreadySafe,
    NotSafe,
    Paused,
    Busy,
    NoWindow,
}

/// Whether the customer's PC goes on to the notice. The way back (`Normal`) never depends on the switch: a PC must be
/// able to leave Safe Mode even if the organization turned the feature off meanwhile.
pub fn decide(kind: Kind, s: &Scene) -> Result<(), Refusal> {
    if !s.ui {
        return Err(Refusal::Unsupported);
    }
    match kind {
        Kind::Safe => {
            if s.switch_hidden {
                return Err(Refusal::SwitchHidden);
            }
            if !s.installed {
                return Err(Refusal::Portable);
            }
            if s.in_safe_mode {
                return Err(Refusal::AlreadySafe);
            }
        }
        Kind::Normal => {
            if !s.in_safe_mode {
                return Err(Refusal::NotSafe);
            }
        }
    }
    if !s.privileged {
        return Err(Refusal::NoService);
    }
    if s.paused {
        return Err(Refusal::Paused);
    }
    if s.busy {
        return Err(Refusal::Busy);
    }
    if !s.window {
        return Err(Refusal::NoWindow);
    }
    Ok(())
}

/// Whether the PC offers the Safe Mode restart to a technician who just logged in: what [`decide`] checks that does not
/// depend on the session. `decide` still runs when the request comes.
pub fn offered(ui: bool, switch_hidden: bool, installed: bool, privileged: bool, in_safe_mode: bool) -> bool {
    let s = Scene { ui, switch_hidden, installed, privileged, in_safe_mode, paused: false, busy: false, window: true };
    decide(Kind::Safe, &s).is_ok()
}

/// The step that failed; the steps before it are undone.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Step {
    Register,
    Bcdedit,
    RunOnce,
    Restart,
}

impl Step {
    fn name(self) -> &'static str {
        match self {
            Step::Register => "ثبت سرویس برای حالت امن",
            Step::Bcdedit => "bcdedit",
            Step::RunOnce => "باز شدن برنامه پس از ورود",
            Step::Restart => "ری‌استارت ویندوز",
        }
    }
}

/// What the technician hears.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Answer {
    Refused(Refusal),
    /// The customer sees the notice now.
    Notice(Kind),
    Cancelled,
    /// The notice ran out; Windows restarts.
    Restarting(Kind),
    Failed(Step),
}

impl Answer {
    pub fn code(self) -> &'static str {
        match self {
            Answer::Refused(Refusal::Unsupported) => "refused-unsupported",
            Answer::Refused(Refusal::SwitchHidden) => "refused-switch",
            Answer::Refused(Refusal::Portable) => "refused-portable",
            Answer::Refused(Refusal::NoService) => "refused-no-service",
            Answer::Refused(Refusal::AlreadySafe) => "refused-already-safe",
            Answer::Refused(Refusal::NotSafe) => "refused-not-safe",
            Answer::Refused(Refusal::Paused) => "refused-paused",
            Answer::Refused(Refusal::Busy) => "refused-busy",
            Answer::Refused(Refusal::NoWindow) => "refused-no-window",
            Answer::Notice(Kind::Safe) => "notice-safe",
            Answer::Notice(Kind::Normal) => "notice-normal",
            Answer::Cancelled => "cancelled",
            Answer::Restarting(Kind::Safe) => "restarting-safe",
            Answer::Restarting(Kind::Normal) => "restarting-normal",
            Answer::Failed(_) => "failed",
        }
    }

    /// The Persian line the technician reads.
    pub fn text(self) -> String {
        match self {
            Answer::Refused(r) => match r {
                Refusal::Unsupported => {
                    "برنامه‌ی مشتری روی این رایانه ری‌استارت در حالت امن را ندارد (نسخه‌ی ۳۲ بیتی).".to_owned()
                }
                Refusal::SwitchHidden => "ری‌استارت در حالت امن برای سازمان این مشتری خاموش است.".to_owned(),
                Refusal::Portable => "دلفین کانکت روی رایانه‌ی مشتری نصب نیست (اجرای بدون نصب)؛ ری‌استارت در حالت امن \
                                      فقط با برنامه‌ی نصب‌شده ممکن است."
                    .to_owned(),
                Refusal::NoService => {
                    "سرویس دلفین کانکت روی رایانه‌ی مشتری با دسترسی کامل اجرا نمی‌شود؛ ری‌استارت انجام نشد.".to_owned()
                }
                Refusal::AlreadySafe => "رایانه‌ی مشتری همین حالا در حالت امن است.".to_owned(),
                Refusal::NotSafe => "رایانه‌ی مشتری در حالت امن نیست.".to_owned(),
                Refusal::Paused => "مشتری جلسه را مکث کرده است؛ ری‌استارت انجام نشد.".to_owned(),
                Refusal::Busy => "یک ری‌استارت دیگر روی این رایانه در راه است.".to_owned(),
                Refusal::NoWindow => "پنجره‌ی دلفین کانکت مشتری باز نیست؛ ری‌استارت انجام نشد.".to_owned(),
            },
            Answer::Notice(Kind::Safe) => "مشتری ۲۰ ثانیه فرصت دارد «لغو» را بزند؛ بعد رایانه در حالت امن دوباره \
                                           راه‌اندازی می‌شود."
                .to_owned(),
            Answer::Notice(Kind::Normal) => "مشتری ۲۰ ثانیه فرصت دارد «لغو» را بزند؛ بعد رایانه به حالت عادی دوباره \
                                             راه‌اندازی می‌شود."
                .to_owned(),
            Answer::Cancelled => "مشتری ری‌استارت را لغو کرد.".to_owned(),
            Answer::Restarting(Kind::Safe) => "رایانه‌ی مشتری در حالت امن (با شبکه) دوباره راه‌اندازی می‌شود. پس از ورود \
                                               مشتری به ویندوز، دلفین کانکت خودش باز می‌شود؛ آن وقت دوباره وصل شوید."
                .to_owned(),
            Answer::Restarting(Kind::Normal) => "رایانه‌ی مشتری به حالت عادی دوباره راه‌اندازی می‌شود. پس از ورود به \
                                                 ویندوز، مشتری دلفین کانکت را باز کند تا دوباره وصل شوید."
                .to_owned(),
            Answer::Failed(step) => format!("ری‌استارت انجام نشد ({}). رایانه‌ی مشتری مثل قبل ماند.", step.name()),
        }
    }
}

/// Seconds of notice left, counted from the moment the notice went out (monotonic milliseconds). The customer window
/// counts the same way (flutter/lib/dolphin/safe_mode.dart `restartSecondsLeft`); the connection only needs [`due`].
#[allow(dead_code)]
pub fn seconds_left(started_ms: u64, now_ms: u64) -> u64 {
    let gone = now_ms.saturating_sub(started_ms) / 1000;
    NOTICE_SECS.saturating_sub(gone)
}

/// Whether the notice ran out.
pub fn due(started_ms: u64, now_ms: u64) -> bool {
    now_ms.saturating_sub(started_ms) >= NOTICE_SECS * 1000
}

/// Windows (`GetSystemMetrics(SM_CLEANBOOT)`): 0 normal boot, 1 Safe Mode, 2 Safe Mode with networking.
pub fn in_safe_mode(clean_boot: i32) -> bool {
    clean_boot != 0
}

/// `HKLM\SYSTEM\CurrentControlSet\Control\SafeBoot\Network\<service>`. `None` for a name that is empty, has a path
/// separator or anything but letters, digits, `_`, `-` and `.`: the key is deleted again later, and a bad name must
/// never point at `SafeBoot\Network` itself or elsewhere.
pub fn safeboot_key(service: &str) -> Option<String> {
    let ok = !service.is_empty()
        && service.len() <= 64
        && service != "."
        && service != ".."
        && service.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.'));
    if ok {
        Some(format!(r"{}\{}", SAFEBOOT_NETWORK, service))
    } else {
        None
    }
}

/// The RunOnce value's name. The leading `*` makes Windows run it in Safe Mode too (RunOnce is skipped there
/// otherwise).
pub fn runonce_name(app: &str) -> String {
    format!("*{}SafeMode", app)
}

/// The RunOnce value: the app itself, quoted (the install folder has spaces), no arguments, so it opens the main
/// window as a double-click would.
pub fn runonce_command(exe: &str) -> String {
    format!("\"{}\"", exe.trim_matches('"'))
}

/// `%SystemRoot%\System32\bcdedit.exe`, by full path (never found through PATH).
pub fn bcdedit_path(system_root: &str) -> String {
    let root = system_root.trim().trim_end_matches('\\');
    let root = if root.is_empty() { r"C:\Windows" } else { root };
    format!(r"{}\System32\bcdedit.exe", root)
}

/// `bcdedit /set {current} safeboot network`: the next boots go to Safe Mode with networking, until removed.
pub fn bcdedit_set_args() -> [&'static str; 4] {
    ["/set", "{current}", "safeboot", "network"]
}

/// `bcdedit /deletevalue {current} safeboot`: back to normal boots.
pub fn bcdedit_delete_args() -> [&'static str; 3] {
    ["/deletevalue", "{current}", "safeboot"]
}

/// What the service does when it starts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BootStep {
    /// Booted in Safe Mode: remove the safeboot value at once, so the next restart is normal whatever happens.
    RemoveSafeboot,
    /// Normal boot: remove our `SafeBoot\Network` entry and RunOnce value if a Safe Mode restart left them.
    CleanLeftovers,
}

pub fn at_service_start(clean_boot: i32) -> BootStep {
    if in_safe_mode(clean_boot) {
        BootStep::RemoveSafeboot
    } else {
        BootStep::CleanLeftovers
    }
}

/// The server's answer to the customer's own «بازگشت به حالت عادی».
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReturnAnswer {
    Restarting,
    NotSafe,
    Busy,
    Stale,
}

impl ReturnAnswer {
    pub fn code(self) -> &'static str {
        match self {
            ReturnAnswer::Restarting => "restarting",
            ReturnAnswer::NotSafe => "not-safe",
            ReturnAnswer::Busy => "busy",
            ReturnAnswer::Stale => "stale",
        }
    }
}

/// The customer's request: a unix time within [`RETURN_FRESH_SECS`] of now, and not the one already handled.
pub fn return_answer(raw: &str, now_secs: i64, last: Option<i64>, in_safe_mode: bool, busy: bool) -> ReturnAnswer {
    let fresh = match raw.trim().parse::<i64>() {
        Ok(t) => (now_secs - t).abs() <= RETURN_FRESH_SECS && last != Some(t),
        Err(_) => false,
    };
    if !fresh {
        ReturnAnswer::Stale
    } else if !in_safe_mode {
        ReturnAnswer::NotSafe
    } else if busy {
        ReturnAnswer::Busy
    } else {
        ReturnAnswer::Restarting
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ok_scene() -> Scene {
        Scene {
            ui: true,
            switch_hidden: false,
            installed: true,
            privileged: true,
            in_safe_mode: false,
            paused: false,
            busy: false,
            window: true,
        }
    }

    #[test]
    fn the_technician_sends_only_our_two_requests() {
        assert_eq!(client_request(REQUEST_ID, "safe"), Some((REQUEST_ID, b"safe".to_vec())));
        assert_eq!(client_request(REQUEST_ID, "normal"), Some((REQUEST_ID, b"normal".to_vec())));
        assert_eq!(client_request(REQUEST_ID, "reboot"), None);
        assert_eq!(client_request("dolphin-paste", "safe"), None);
    }

    #[test]
    fn the_customer_reads_only_our_requests() {
        assert_eq!(request(REQUEST_ID, b"safe"), Some(Kind::Safe));
        assert_eq!(request(REQUEST_ID, b"normal"), Some(Kind::Normal));
        assert_eq!(request(REQUEST_ID, b"Safe"), None);
        assert_eq!(request(REQUEST_ID, &[0xff, 0xfe]), None);
        assert_eq!(request("dolphin-kbd", b"safe"), None);
        assert!(is_request(REQUEST_ID));
        assert!(!is_request("dolphin-paste"));
    }

    #[test]
    fn safe_mode_is_refused_when_the_switch_is_hidden_or_the_app_portable() {
        assert_eq!(decide(Kind::Safe, &ok_scene()), Ok(()));
        let s = Scene { switch_hidden: true, ..ok_scene() };
        assert_eq!(decide(Kind::Safe, &s), Err(Refusal::SwitchHidden));
        let s = Scene { installed: false, ..ok_scene() };
        assert_eq!(decide(Kind::Safe, &s), Err(Refusal::Portable));
        let s = Scene { privileged: false, ..ok_scene() };
        assert_eq!(decide(Kind::Safe, &s), Err(Refusal::NoService));
        let s = Scene { in_safe_mode: true, ..ok_scene() };
        assert_eq!(decide(Kind::Safe, &s), Err(Refusal::AlreadySafe));
        let s = Scene { ui: false, ..ok_scene() };
        assert_eq!(decide(Kind::Safe, &s), Err(Refusal::Unsupported));
    }

    #[test]
    fn a_pause_a_running_restart_or_no_window_refuse_both_kinds() {
        for kind in [Kind::Safe, Kind::Normal] {
            let base = Scene { in_safe_mode: kind == Kind::Normal, ..ok_scene() };
            assert_eq!(decide(kind, &base), Ok(()));
            assert_eq!(decide(kind, &Scene { paused: true, ..base }), Err(Refusal::Paused));
            assert_eq!(decide(kind, &Scene { busy: true, ..base }), Err(Refusal::Busy));
            assert_eq!(decide(kind, &Scene { window: false, ..base }), Err(Refusal::NoWindow));
        }
    }

    #[test]
    fn the_way_back_ignores_the_switch_but_needs_safe_mode() {
        let s = Scene { in_safe_mode: true, switch_hidden: true, installed: false, ..ok_scene() };
        assert_eq!(decide(Kind::Normal, &s), Ok(()));
        assert_eq!(decide(Kind::Normal, &ok_scene()), Err(Refusal::NotSafe));
    }

    #[test]
    fn the_offer_follows_the_switch_the_install_and_the_service() {
        assert!(offered(true, false, true, true, false));
        assert!(!offered(true, true, true, true, false));
        assert!(!offered(true, false, false, true, false));
        assert!(!offered(true, false, true, false, false));
        assert!(!offered(true, false, true, true, true));
        assert!(!offered(false, false, true, true, false));
    }

    #[test]
    fn every_answer_has_a_code_and_a_persian_line() {
        let all = [
            Answer::Refused(Refusal::Unsupported),
            Answer::Refused(Refusal::SwitchHidden),
            Answer::Refused(Refusal::Portable),
            Answer::Refused(Refusal::NoService),
            Answer::Refused(Refusal::AlreadySafe),
            Answer::Refused(Refusal::NotSafe),
            Answer::Refused(Refusal::Paused),
            Answer::Refused(Refusal::Busy),
            Answer::Refused(Refusal::NoWindow),
            Answer::Notice(Kind::Safe),
            Answer::Notice(Kind::Normal),
            Answer::Cancelled,
            Answer::Restarting(Kind::Safe),
            Answer::Restarting(Kind::Normal),
            Answer::Failed(Step::Bcdedit),
        ];
        let mut codes: Vec<&str> = all.iter().map(|a| a.code()).collect();
        codes.sort();
        codes.dedup();
        assert_eq!(codes.len(), all.len());
        for a in all {
            let t = a.text();
            assert!(!t.is_empty() && t.chars().count() <= 160, "{}", a.code());
            assert!(!t.contains("  "), "a line break in a literal left spaces: {}", a.code());
        }
        assert!(Answer::Failed(Step::RunOnce).text().contains("باز شدن برنامه"));
        assert!(Answer::Refused(Refusal::SwitchHidden).text().contains("خاموش"));
    }

    #[test]
    fn the_notice_counts_twenty_seconds() {
        assert_eq!(seconds_left(1_000, 1_000), 20);
        assert_eq!(seconds_left(1_000, 1_999), 20);
        assert_eq!(seconds_left(1_000, 2_000), 19);
        assert_eq!(seconds_left(1_000, 20_999), 1);
        assert_eq!(seconds_left(1_000, 21_000), 0);
        assert_eq!(seconds_left(1_000, 99_000), 0);
        assert_eq!(seconds_left(5_000, 1_000), 20); // a clock that went back does not cut it short
        assert!(!due(1_000, 20_999));
        assert!(due(1_000, 21_000));
    }

    #[test]
    fn audit_actions_and_notices_are_the_contract_names() {
        assert_eq!(Kind::Safe.audit_action(), "safe_mode");
        assert_eq!(Kind::Normal.audit_action(), "normal_restart");
        assert_eq!(Kind::from_cm_notice(Kind::Safe.cm_notice()), Some(Kind::Safe));
        assert_eq!(Kind::from_cm_notice(Kind::Normal.cm_notice()), Some(Kind::Normal));
        assert_eq!(Kind::from_cm_notice(CM_CANCEL), None);
        assert_eq!(Kind::from_cm_notice("keyboard"), None);
    }

    #[test]
    fn the_safeboot_key_is_only_ever_our_service() {
        assert_eq!(
            safeboot_key("DolphinConnect").as_deref(),
            Some(r"SYSTEM\CurrentControlSet\Control\SafeBoot\Network\DolphinConnect")
        );
        for bad in ["", ".", "..", r"a\b", "a/b", "Dolphin Connect", r"..\Minimal", "a\0b"] {
            assert_eq!(safeboot_key(bad), None, "{:?}", bad);
        }
        assert_eq!(safeboot_key(&"x".repeat(65)), None);
    }

    #[test]
    fn the_command_lines_are_exact() {
        assert_eq!(bcdedit_path(r"C:\Windows"), r"C:\Windows\System32\bcdedit.exe");
        assert_eq!(bcdedit_path(r"D:\WINDOWS\"), r"D:\WINDOWS\System32\bcdedit.exe");
        assert_eq!(bcdedit_path(""), r"C:\Windows\System32\bcdedit.exe");
        assert_eq!(bcdedit_set_args().join(" "), "/set {current} safeboot network");
        assert_eq!(bcdedit_delete_args().join(" "), "/deletevalue {current} safeboot");
        assert_eq!(runonce_name("DolphinConnect"), "*DolphinConnectSafeMode");
        assert_eq!(
            runonce_command(r"C:\Program Files\DolphinConnect\DolphinConnect.exe"),
            r#""C:\Program Files\DolphinConnect\DolphinConnect.exe""#
        );
        assert_eq!(runonce_command(r#""C:\a b\x.exe""#), r#""C:\a b\x.exe""#);
        assert_eq!(RUNONCE_KEY, r"SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce");
        assert_eq!(SAFEBOOT_VALUE, "Service");
        assert_eq!(SAFEBOOT_OPTION, r"SYSTEM\CurrentControlSet\Control\SafeBoot\Option");
    }

    #[test]
    fn booted_in_safe_mode_the_value_goes_at_once() {
        assert!(!in_safe_mode(0));
        assert!(in_safe_mode(1));
        assert!(in_safe_mode(2));
        assert_eq!(at_service_start(2), BootStep::RemoveSafeboot);
        assert_eq!(at_service_start(1), BootStep::RemoveSafeboot);
        assert_eq!(at_service_start(0), BootStep::CleanLeftovers);
    }

    #[test]
    fn the_customers_return_is_fresh_once_and_only_in_safe_mode() {
        let now = 1_800_000_000;
        assert_eq!(return_answer("1800000000", now, None, true, false), ReturnAnswer::Restarting);
        assert_eq!(return_answer("1799999950", now, None, true, false), ReturnAnswer::Restarting);
        assert_eq!(return_answer("1799999000", now, None, true, false), ReturnAnswer::Stale);
        assert_eq!(return_answer("1800000000", now, Some(1_800_000_000), true, false), ReturnAnswer::Stale);
        assert_eq!(return_answer("Y", now, None, true, false), ReturnAnswer::Stale);
        assert_eq!(return_answer("1800000000", now, None, false, false), ReturnAnswer::NotSafe);
        assert_eq!(return_answer("1800000000", now, None, true, true), ReturnAnswer::Busy);
        assert_eq!(ReturnAnswer::Restarting.code(), "restarting");
    }
}
