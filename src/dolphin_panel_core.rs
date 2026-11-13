//! Dolphin Connect (Plan 18 Phase 3: DD-50 ready-made texts, DD-6 the customer's keyboard language): the rules for the
//! two things the technician's session window asks the customer's PC to do, standard library only, so CI tests them
//! alone (`rustc --edition 2021 --test src/dolphin_panel_core.rs`). The Windows side is src/dolphin_panel.rs; the hooks
//! are in src/flutter_ffi.rs (`session_set_common`), src/ui_session_interface.rs and src/server/connection.rs (marked
//! `Dolphin Connect (DD-50, DD-6)`); the technician's window is flutter/lib/dolphin/side_pane.dart.
//!
//! No new network message. Both requests ride on `Misc::PluginRequest { id, content }`, which the protocol already
//! has and nothing in this fork sends or handles (upstream's plugin framework is not built here): an older customer
//! app drops it unread, so nothing happens there and the technician's window says the app is old. The answer comes
//! back as the existing `MessageBox` with [`RESULT_MSGTYPE`]; the Dolphin technician app shows it as a short line over
//! the picture instead of a dialog.
//!
//! On the customer's PC both act only for an authorised remote session whose technician may use the keyboard (the
//! customer's switch, DD-45) and that is not paused (DD-46); a paste also needs the clipboard switch. Neither works
//! into a window of a program run as administrator when our server is not elevated itself (Windows UIPI): that is
//! reported, not tried.

/// `PluginRequest.id` for a paste; the content is the text (UTF-8).
pub const PASTE_REQUEST: &str = "dolphin-paste";
/// `PluginRequest.id` for the keyboard language; the content is [`Lang::code`].
pub const KBD_REQUEST: &str = "dolphin-kbd";
/// `MessageBox.msgtype` of the answer; `title` is [`Outcome::code`], `text` the Persian line.
pub const RESULT_MSGTYPE: &str = "dolphin-panel";

/// The portal cuts a ready-made text at 2000 characters (app/src/lib/app-bridge.ts `pasteMessage`); longer is refused.
pub const PASTE_MAX_CHARS: usize = 2000;
/// Upstream sets the clipboard on its own thread; the paste keys wait this long for it.
pub const PASTE_DELAY_MS: u64 = 300;

/// The two languages the technician can pick.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Lang {
    Persian,
    English,
}

impl Lang {
    pub fn parse(code: &str) -> Option<Lang> {
        match code {
            "fa" => Some(Lang::Persian),
            "en" => Some(Lang::English),
            _ => None,
        }
    }

    pub fn code(self) -> &'static str {
        match self {
            Lang::Persian => "fa",
            Lang::English => "en",
        }
    }

    /// Windows language ID: Persian 0x0429, English (United States) 0x0409.
    pub fn langid(self) -> u16 {
        match self {
            Lang::Persian => 0x0429,
            Lang::English => 0x0409,
        }
    }

    /// Any English layout (US, UK, ...) will do: the primary language is the low 10 bits of the language ID.
    fn matches(self, langid: u16) -> bool {
        match self {
            Lang::Persian => langid == 0x0429,
            Lang::English => langid & 0x03ff == 0x09,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Lang::Persian => "فارسی",
            Lang::English => "انگلیسی",
        }
    }
}

/// What the customer's PC is asked to do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Request {
    Paste(String),
    Keyboard(Lang),
}

/// A text the PC may paste: not empty, at most [`PASTE_MAX_CHARS`], no control characters but tab and line breaks.
pub fn paste_text(raw: &str) -> Option<String> {
    if raw.trim().is_empty() || raw.chars().count() > PASTE_MAX_CHARS {
        return None;
    }
    if raw.chars().any(|c| c.is_control() && !matches!(c, '\t' | '\n' | '\r')) {
        return None;
    }
    Some(raw.to_owned())
}

/// Customer's PC: the request in a `PluginRequest`, or `None` for anything else (left alone, as before).
pub fn request(id: &str, content: &[u8]) -> Option<Request> {
    let text = std::str::from_utf8(content).ok()?;
    match id {
        PASTE_REQUEST => paste_text(text).map(Request::Paste),
        KBD_REQUEST => Lang::parse(text).map(Request::Keyboard),
        _ => None,
    }
}

/// Technician's app (`session_set_common` key and value): the `PluginRequest` to send, or `None` when the key is not
/// ours or the value is bad (nothing is sent).
pub fn client_request(key: &str, value: &str) -> Option<(&'static str, Vec<u8>)> {
    match key {
        PASTE_REQUEST => paste_text(value).map(|t| (PASTE_REQUEST, t.into_bytes())),
        KBD_REQUEST => Lang::parse(value).map(|l| (KBD_REQUEST, l.code().as_bytes().to_vec())),
        _ => None,
    }
}

/// How a request ended on the customer's PC.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    Pasted,
    Switched(Lang),
    /// The foreground window belongs to a program run as administrator and our server is not elevated.
    Elevated,
    /// No foreground window (the lock or sign-in screen, or nothing focused).
    NoWindow,
    NotInstalled(Lang),
    /// The customer turned the keyboard off or paused.
    InputOff,
    ClipboardOff,
    Failed,
    /// Not a Windows PC.
    Unsupported,
}

impl Outcome {
    pub fn code(self) -> &'static str {
        match self {
            Outcome::Pasted => "pasted",
            Outcome::Switched(Lang::Persian) => "switched-fa",
            Outcome::Switched(Lang::English) => "switched-en",
            Outcome::Elevated => "elevated",
            Outcome::NoWindow => "no-window",
            Outcome::NotInstalled(_) => "not-installed",
            Outcome::InputOff => "input-off",
            Outcome::ClipboardOff => "clipboard-off",
            Outcome::Failed => "failed",
            Outcome::Unsupported => "unsupported",
        }
    }

    /// The line the technician reads.
    pub fn text(self) -> String {
        match self {
            Outcome::Pasted => "متن در رایانه‌ی مشتری چسبانده شد.".to_owned(),
            Outcome::Switched(l) => format!("زبان صفحه‌کلید مشتری {} شد.", l.name()),
            Outcome::Elevated => "پنجره‌ی جلوی مشتری برنامه‌ی با دسترسی مدیر است؛ روی آن انجام نشد.".to_owned(),
            Outcome::NoWindow => "روی صفحه‌ی مشتری پنجره‌ای فعال نیست (شاید صفحه‌ی قفل)؛ انجام نشد.".to_owned(),
            Outcome::NotInstalled(l) => format!("زبان {} روی رایانه‌ی مشتری نصب نیست.", l.name()),
            Outcome::InputOff => "مشتری ماوس و صفحه‌کلید را خاموش کرده یا مکث کرده است؛ انجام نشد.".to_owned(),
            Outcome::ClipboardOff => "مشتری «کپی و چسباندن» را خاموش کرده است؛ متن چسبانده نشد.".to_owned(),
            Outcome::Failed => "انجام نشد؛ دوباره امتحان کنید.".to_owned(),
            Outcome::Unsupported => "این کار فقط روی ویندوز انجام می‌شود.".to_owned(),
        }
    }
}

/// What the PC looks like when a request comes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Scene {
    /// The technician may use the keyboard now (customer's switch on, not paused).
    pub input: bool,
    /// The clipboard switch is on (and not paused).
    pub clipboard: bool,
    pub has_window: bool,
    /// Our server runs as SYSTEM or elevated: Windows lets it reach any window.
    pub self_elevated: bool,
    pub foreground_elevated: bool,
}

/// Checks shared by both requests, in the order the technician needs to hear them.
fn refusal(scene: &Scene) -> Option<Outcome> {
    if !scene.input {
        return Some(Outcome::InputOff);
    }
    if !scene.has_window {
        return Some(Outcome::NoWindow);
    }
    if scene.foreground_elevated && !scene.self_elevated {
        return Some(Outcome::Elevated);
    }
    None
}

/// A paste may go ahead (`None`) or is refused with the reason.
pub fn plan_paste(scene: &Scene) -> Option<Outcome> {
    if scene.input && !scene.clipboard {
        return Some(Outcome::ClipboardOff);
    }
    refusal(scene)
}

/// The keyboard layout to ask the foreground window for (`Ok(hkl)`), from the PC's installed layouts, or the reason.
pub fn plan_layout(scene: &Scene, installed: &[usize], lang: Lang) -> Result<usize, Outcome> {
    if let Some(no) = refusal(scene) {
        return Err(no);
    }
    pick_layout(installed, lang).ok_or(Outcome::NotInstalled(lang))
}

/// The first installed layout (HKL) of the language: an HKL's low word is its language ID. Only installed layouts are
/// asked for, so the customer's PC never gains a layout it did not have.
pub fn pick_layout(installed: &[usize], lang: Lang) -> Option<usize> {
    installed.iter().copied().find(|hkl| hkl & 0xffff != 0 && lang.matches((hkl & 0xffff) as u16))
}

/// After posting or sending input: Windows says access denied (error 5) when UIPI stopped it.
pub fn sent_outcome(ok: bool, last_error: i32, done: Outcome) -> Outcome {
    if ok {
        done
    } else if last_error == 5 {
        Outcome::Elevated
    } else {
        Outcome::Failed
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const OPEN: Scene = Scene { input: true, clipboard: true, has_window: true, self_elevated: false, foreground_elevated: false };

    #[test]
    fn requests_parse_only_our_ids_and_good_values() {
        assert_eq!(request(PASTE_REQUEST, "dir C:\\".as_bytes()), Some(Request::Paste("dir C:\\".into())));
        assert_eq!(request(KBD_REQUEST, b"fa"), Some(Request::Keyboard(Lang::Persian)));
        assert_eq!(request(KBD_REQUEST, b"en"), Some(Request::Keyboard(Lang::English)));
        assert_eq!(request(KBD_REQUEST, b"de"), None);
        assert_eq!(request("some-plugin", b"fa"), None);
        assert_eq!(request(PASTE_REQUEST, &[0xff, 0xfe]), None, "not UTF-8");
    }

    #[test]
    fn persian_text_and_line_breaks_paste() {
        let t = "سلام\r\nخط دوم\tستون";
        assert_eq!(paste_text(t).as_deref(), Some(t));
    }

    #[test]
    fn empty_long_or_control_text_is_refused() {
        assert_eq!(paste_text(""), None);
        assert_eq!(paste_text("  \n"), None);
        assert_eq!(paste_text("a\u{0}b"), None);
        assert_eq!(paste_text("a\u{1b}[2J"), None);
        let max: String = "ب".repeat(PASTE_MAX_CHARS);
        assert!(paste_text(&max).is_some(), "the limit counts characters, not bytes");
        assert_eq!(paste_text(&format!("{max}x")), None);
    }

    #[test]
    fn the_client_sends_only_our_keys_with_good_values() {
        assert_eq!(client_request(KBD_REQUEST, "fa"), Some((KBD_REQUEST, b"fa".to_vec())));
        assert_eq!(client_request(PASTE_REQUEST, "x"), Some((PASTE_REQUEST, b"x".to_vec())));
        assert_eq!(client_request(PASTE_REQUEST, ""), None);
        assert_eq!(client_request(KBD_REQUEST, "FA"), None);
        assert_eq!(client_request("continue-insecure-connection", "Y"), None, "upstream's key stays upstream's");
    }

    #[test]
    fn layouts_are_picked_by_language_from_the_installed_ones() {
        let installed = [0x0409_0409usize, 0xf03a_0429, 0x0809_0809];
        assert_eq!(pick_layout(&installed, Lang::Persian), Some(0xf03a_0429));
        assert_eq!(pick_layout(&installed, Lang::English), Some(0x0409_0409));
        assert_eq!(pick_layout(&[0x0809_0809], Lang::English), Some(0x0809_0809), "UK English is English");
        assert_eq!(pick_layout(&[0x0409_0409], Lang::Persian), None);
        assert_eq!(pick_layout(&[0x0000_0000], Lang::English), None);
    }

    #[test]
    fn a_missing_language_is_reported_not_installed() {
        assert_eq!(plan_layout(&OPEN, &[0x0409_0409], Lang::Persian), Err(Outcome::NotInstalled(Lang::Persian)));
        assert_eq!(plan_layout(&OPEN, &[0x0409_0409, 0x0429_0429], Lang::Persian), Ok(0x0429_0429));
    }

    #[test]
    fn an_elevated_window_is_reported_unless_we_are_elevated_too() {
        let elevated = Scene { foreground_elevated: true, ..OPEN };
        assert_eq!(plan_layout(&elevated, &[0x0429_0429], Lang::Persian), Err(Outcome::Elevated));
        assert_eq!(plan_paste(&elevated), Some(Outcome::Elevated));
        let service = Scene { self_elevated: true, ..elevated };
        assert_eq!(plan_layout(&service, &[0x0429_0429], Lang::Persian), Ok(0x0429_0429));
        assert_eq!(plan_paste(&service), None);
    }

    #[test]
    fn the_customers_switches_and_pause_win() {
        let off = Scene { input: false, ..OPEN };
        assert_eq!(plan_layout(&off, &[0x0429_0429], Lang::Persian), Err(Outcome::InputOff));
        assert_eq!(plan_paste(&off), Some(Outcome::InputOff));
        assert_eq!(plan_paste(&Scene { clipboard: false, ..OPEN }), Some(Outcome::ClipboardOff));
        assert_eq!(plan_paste(&OPEN), None);
    }

    #[test]
    fn no_window_means_nothing_is_sent() {
        let locked = Scene { has_window: false, ..OPEN };
        assert_eq!(plan_paste(&locked), Some(Outcome::NoWindow));
        assert_eq!(plan_layout(&locked, &[0x0429_0429], Lang::Persian), Err(Outcome::NoWindow));
    }

    #[test]
    fn access_denied_after_sending_reads_as_elevated() {
        assert_eq!(sent_outcome(true, 0, Outcome::Pasted), Outcome::Pasted);
        assert_eq!(sent_outcome(false, 5, Outcome::Pasted), Outcome::Elevated);
        assert_eq!(sent_outcome(false, 87, Outcome::Pasted), Outcome::Failed);
    }

    #[test]
    fn every_outcome_has_a_code_and_a_persian_line() {
        let all = [
            Outcome::Pasted,
            Outcome::Switched(Lang::Persian),
            Outcome::Switched(Lang::English),
            Outcome::Elevated,
            Outcome::NoWindow,
            Outcome::NotInstalled(Lang::Persian),
            Outcome::InputOff,
            Outcome::ClipboardOff,
            Outcome::Failed,
            Outcome::Unsupported,
        ];
        for o in all {
            assert!(!o.code().is_empty());
            assert!(o.text().chars().any(|c| ('\u{0600}'..='\u{06ff}').contains(&c)), "{:?}", o);
            assert!(o.text().chars().count() <= 120);
        }
        assert_eq!(Outcome::Switched(Lang::Persian).text(), "زبان صفحه‌کلید مشتری فارسی شد.");
        assert_eq!(Outcome::Elevated.code(), "elevated");
    }
}
