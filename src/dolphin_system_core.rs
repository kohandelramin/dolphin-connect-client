//! Dolphin Connect, Plan 18 Phase 2 (ADR-0016): the rules behind the customer app's tray (DD-35, DD-47), «شروع / توقف
//! اشتراک» (DD-34) and the fixed receive folder (DD-12). Standard library only, so CI tests it alone
//! (`rustc --edition 2021 --test src/dolphin_system_core.rs`); `src/dolphin_system.rs` wires it into the app.

use std::path::{Component, Path, PathBuf};

/// The portal's feature switches (app/src/lib/switches.ts, DD-4), pushed as one JSON object on the heartbeat.
/// Read the same way as `flutter/lib/dolphin/switches.dart`.
pub const SWITCHES_OPTION: &str = "dolphin-switches";
pub const SWITCH_SHARE_TOGGLE: &str = "share-toggle";
pub const SWITCH_STAY_IN_TRAY: &str = "stay-in-tray";
pub const SWITCH_RECEIVE_FOLDER: &str = "receive-folder";

/// "Y" while the customer has stopped sharing (DD-34). Set by the home screen, read by the server process.
pub const SHARE_OFF_OPTION: &str = "dolphin-share-off";

/// What a refused technician reads. Translation keys, so the technician app shows them in its own words
/// (`dolphin/rebrand.py` FA_ADD).
pub const SHARE_OFF_LOGIN_ERROR: &str = "dolphin_share_stopped";
pub const RECEIVE_ONLY_ERROR: &str = "dolphin_receive_folder_only";

/// DD-12: under the customer's own Downloads, which every Windows user owns and can write to.
pub const RECEIVE_FOLDER_NAME: &str = "دریافتی دلفین";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SwitchMode {
    Hidden,
    Available,
    Forced,
}

impl SwitchMode {
    fn from_name(s: &str) -> Option<Self> {
        match s {
            "hidden" => Some(Self::Hidden),
            "available" => Some(Self::Available),
            "forced" => Some(Self::Forced),
            _ => None,
        }
    }
}

/// The defaults when the portal has said nothing (keep in step with kSwitchDefaults in switches.dart). Unknown keys
/// are hidden: the app never turns on a feature the portal does not know.
pub fn switch_default(key: &str) -> SwitchMode {
    match key {
        "direct-route" => SwitchMode::Forced,
        SWITCH_SHARE_TOGGLE | SWITCH_STAY_IN_TRAY | SWITCH_RECEIVE_FOLDER | "diagnostics-upload" => {
            SwitchMode::Available
        }
        SWITCH_REMOTE_SOUND => SwitchMode::Available,
        _ => SwitchMode::Hidden,
    }
}

/// One switch from the pushed option. Anything unexpected (missing, "-", bad JSON, an unknown mode) falls back to the
/// default for that key alone, as in switches.dart.
pub fn switch_mode(raw: &str, key: &str) -> SwitchMode {
    flat_string_pairs(raw)
        .and_then(|pairs| {
            pairs
                .into_iter()
                .rev() // a repeated key: the last one wins, like jsonDecode
                .find(|(k, _)| k == key)
                .and_then(|(_, v)| SwitchMode::from_name(&v))
        })
        .unwrap_or_else(|| switch_default(key))
}

/// The string-valued members of a JSON object; other values are skipped. `None` when it is not a JSON object.
fn flat_string_pairs(raw: &str) -> Option<Vec<(String, String)>> {
    let mut p = Parser { s: raw.as_bytes(), i: 0 };
    p.ws();
    p.eat(b'{')?;
    let mut out = Vec::new();
    p.ws();
    if p.peek() == Some(b'}') {
        p.i += 1;
        return p.end().then_some(out);
    }
    loop {
        p.ws();
        let k = p.string()?;
        p.ws();
        p.eat(b':')?;
        p.ws();
        if p.peek() == Some(b'"') {
            let v = p.string()?;
            out.push((k, v));
        } else {
            p.skip_value()?;
        }
        p.ws();
        match p.peek()? {
            b',' => p.i += 1,
            b'}' => {
                p.i += 1;
                return p.end().then_some(out);
            }
            _ => return None,
        }
    }
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}

impl Parser<'_> {
    fn peek(&self) -> Option<u8> {
        self.s.get(self.i).copied()
    }
    fn ws(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\n' | b'\r' | b'\t')) {
            self.i += 1;
        }
    }
    fn eat(&mut self, c: u8) -> Option<()> {
        (self.peek()? == c).then(|| self.i += 1)
    }
    fn end(&mut self) -> bool {
        self.ws();
        self.i == self.s.len()
    }
    fn string(&mut self) -> Option<String> {
        self.eat(b'"')?;
        let mut out = Vec::<u8>::new();
        loop {
            let c = self.peek()?;
            self.i += 1;
            match c {
                b'"' => return String::from_utf8(out).ok(),
                b'\\' => {
                    let e = self.peek()?;
                    self.i += 1;
                    match e {
                        b'"' | b'\\' | b'/' => out.push(e),
                        b'n' | b't' | b'r' | b'b' | b'f' => out.push(b' '),
                        b'u' => {
                            let hex = std::str::from_utf8(self.s.get(self.i..self.i + 4)?).ok()?;
                            let ch = char::from_u32(u32::from_str_radix(hex, 16).ok()?).unwrap_or('\u{fffd}');
                            self.i += 4;
                            out.extend_from_slice(ch.encode_utf8(&mut [0; 4]).as_bytes());
                        }
                        _ => return None,
                    }
                }
                c if c < 0x20 => return None,
                _ => out.push(c),
            }
        }
    }
    /// A number, true/false/null, or a nested array or object (strings inside respected).
    fn skip_value(&mut self) -> Option<()> {
        match self.peek()? {
            b'"' => self.string().map(|_| ()),
            b'{' | b'[' => {
                let mut depth = 0usize;
                loop {
                    match self.peek()? {
                        b'"' => {
                            self.string()?;
                            continue;
                        }
                        b'{' | b'[' => depth += 1,
                        b'}' | b']' => {
                            depth -= 1;
                            if depth == 0 {
                                self.i += 1;
                                return Some(());
                            }
                        }
                        _ => {}
                    }
                    self.i += 1;
                }
            }
            _ => {
                let start = self.i;
                while matches!(self.peek(), Some(c) if c.is_ascii_alphanumeric() || matches!(c, b'-' | b'+' | b'.')) {
                    self.i += 1;
                }
                (self.i > start).then_some(())
            }
        }
    }
}

// ---- DD-34: «شروع / توقف اشتراک» ----

/// Whether every new connection is refused right now: the customer stopped sharing and the switch shows the control.
/// With the switch hidden the control is not there, so an old "Y" left behind must not lock the PC.
pub fn sharing_stopped(share_toggle: SwitchMode, option: &str) -> bool {
    share_toggle != SwitchMode::Hidden && option == "Y"
}

/// The heartbeat's `dolphin_share` field, so «رایانه‌ها» can show «اشتراک متوقف».
pub fn heartbeat_share(stopped: bool) -> &'static str {
    if stopped {
        "stopped"
    } else {
        "on"
    }
}

// ---- DD-41: the remote printer (owner 2026-11-13: off unless an organization turns it on) ----

#[cfg_attr(not(feature = "flutter"), allow(dead_code))]
pub const SWITCH_REMOTE_PRINTER: &str = "remote-printer";

/// Whether a print job from the customer's «DolphinConnect Printer» goes to the technician. `permitted` is upstream's
/// own answer (`enable-remote-printer`, on unless set to "N", and the server's control permissions). Hidden refuses
/// every job whatever the option says; forced sends it even when the option was turned off; available leaves it to
/// upstream's answer, which the customer's switch in About sets. Only the Flutter build prints (the x86 build has no
/// printer service).
#[cfg_attr(not(feature = "flutter"), allow(dead_code))]
pub fn printer_forward(mode: SwitchMode, permitted: bool) -> bool {
    match mode {
        SwitchMode::Hidden => false,
        SwitchMode::Available => permitted,
        SwitchMode::Forced => true,
    }
}

/// Whether a session subscribes to upstream's printer service, whose thread waits on the printer adapter in a loop
/// (local only, no network). Hidden means no job can ever be sent, so the loop is not started at all.
#[cfg_attr(not(feature = "flutter"), allow(dead_code))]
pub fn printer_service_wanted(mode: SwitchMode) -> bool {
    mode != SwitchMode::Hidden
}

// ---- DD-31: the customer's computer sound (owner 2026-11-13: yes, off by default) ----

/// The portal's switch for «صدای رایانه‌ی مشتری». Available (the default): the technician's toolbar shows the button
/// and every session starts with the sound off. Hidden: the customer PC sends no sound at all and tells the
/// technician's app so at login. Forced reads as available: sound adds traffic, so it never starts by itself.
pub const SWITCH_REMOTE_SOUND: &str = "remote-sound";

/// `platform_additions` key: whether the customer PC sends its sound in this session (the technician app has no
/// heartbeat and never sees the switches; flutter/lib/dolphin/sound.dart reads this).
pub const PLATFORM_SOUND_OFFERED: &str = "dolphin_sound_offered";

/// Whether the switch lets the customer PC send its sound.
pub fn sound_offered(mode: SwitchMode) -> bool {
    mode != SwitchMode::Hidden
}

/// [`sound_offered`] from the pushed option as stored (`dolphin-switches`).
pub fn sound_offered_by(raw_switches: &str) -> bool {
    sound_offered(switch_mode(raw_switches, SWITCH_REMOTE_SOUND))
}

/// Whether a new session of this kind starts with the customer's sound off (upstream starts it on, from the peer's
/// saved «Mute»). Every remote-desktop session does; other kinds carry no sound. A reconnect inside the session keeps
/// the technician's choice, since it reuses the session's settings.
pub fn session_starts_muted(is_remote_desktop: bool) -> bool {
    is_remote_desktop
}

// ---- RO-4: one-way transfer, RO-5: lock on end (Plan 19; owner 2026-11-14, both off unless an organization asks) ----

/// The portal's switch for one-way transfer. Hidden (the default): upstream's behaviour as built (both ways). Available
/// or forced: the technician can send files to the customer but cannot take files or the customer's clipboard.
pub const SWITCH_ONE_WAY_TRANSFER: &str = "one-way-transfer";

/// Upstream's built-in options this switch turns on. Upstream reads them with `get_builtin_option` in the customer's
/// server process (src/server/connection.rs: file actions that read, rename or delete on this PC, the clipboard
/// service, file-clipboard data requests) and in the session window (src/ui_cm_interface.rs, the file clipboard).
pub const ONE_WAY_FILE_TRANSFER: &str = "one-way-file-transfer";
pub const ONE_WAY_CLIPBOARD: &str = "one-way-clipboard-redirection";

pub fn is_one_way_key(key: &str) -> bool {
    key == ONE_WAY_FILE_TRANSFER || key == ONE_WAY_CLIPBOARD
}

pub fn one_way_on(mode: SwitchMode) -> bool {
    mode != SwitchMode::Hidden
}

/// What `get_builtin_option(key)` answers for one of upstream's one-way keys: "Y" while the switch is on, else None
/// (the compiled-in value stands). Computed from the pushed option at each read: nothing is stored, and the switch
/// can only add the restriction, never lift a compiled-in one.
pub fn builtin_override(key: &str, raw_switches: &str) -> Option<&'static str> {
    if is_one_way_key(key) && one_way_on(switch_mode(raw_switches, SWITCH_ONE_WAY_TRANSFER)) {
        Some("Y")
    } else {
        None
    }
}

/// The portal's switch for locking the customer's Windows when a session ends. Hidden (the default): upstream's
/// behaviour, only the technician's own «Lock after session end» (off unless he turns it on). Available or forced:
/// every session locks the PC at its end, as if the technician had turned it on. Upstream's other conditions stay
/// (src/server/connection.rs `on_close`: a close that may lock, keyboard permission, not a session taken over by its
/// own reconnect).
pub const SWITCH_LOCK_ON_END: &str = "lock-on-end";

pub fn lock_at_end(technician_asked: bool, mode: SwitchMode) -> bool {
    technician_asked || mode != SwitchMode::Hidden
}

/// [`lock_at_end`] from the pushed option as stored (`dolphin-switches`).
pub fn lock_at_end_by(technician_asked: bool, raw_switches: &str) -> bool {
    lock_at_end(technician_asked, switch_mode(raw_switches, SWITCH_LOCK_ON_END))
}

// ---- DD-12: the fixed receive folder ----

/// `<home>\Downloads\دریافتی دلفین`.
pub fn receive_dir(home: &Path) -> PathBuf {
    home.join("Downloads").join(RECEIVE_FOLDER_NAME)
}

/// The folder the file manager opens when the technician has none saved (the first ReadDir has an empty path): the
/// receive folder unless the switch is hidden (upstream: the home folder).
pub fn opens_receive_dir(mode: SwitchMode) -> bool {
    mode != SwitchMode::Hidden
}

/// The folder sent at login is the technician's last one for this PC. When the folder is forced it is ignored, so the
/// file manager always opens in the receive folder.
pub fn login_dir(mode: SwitchMode, client_dir: &str) -> &str {
    if mode == SwitchMode::Forced {
        ""
    } else {
        client_dir
    }
}

/// When the folder is forced, a new file or folder from the technician lands only inside the receive folder (`target`
/// already resolved by the caller, symlinks included). Paths with `..` are refused. Windows paths compare without case.
pub fn write_allowed(mode: SwitchMode, receive: &Path, target: &Path, ignore_case: bool) -> bool {
    if mode != SwitchMode::Forced {
        return true;
    }
    if target.components().any(|c| c == Component::ParentDir) {
        return false;
    }
    let norm = |p: &Path| -> Vec<String> {
        p.components()
            .filter(|c| *c != Component::CurDir)
            .map(|c| {
                let s = c.as_os_str().to_string_lossy().trim_end_matches(['\\', '/']).to_string();
                if ignore_case {
                    s.to_lowercase()
                } else {
                    s
                }
            })
            .collect()
    };
    let (base, t) = (norm(receive), norm(target));
    t.len() > base.len() && t[..base.len()] == base[..]
}

// ---- DD-35 / DD-47: the tray ----

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrayState {
    /// The window is not open (not even in the tray): nobody can connect, so no icon.
    Closed,
    Ready,
    Connected,
    Offline,
    Stopped,
}

/// A live session wins: it is the most important thing to show, and on an installed app it can outlive the window.
pub fn tray_state(window_open: bool, online: bool, sessions: usize, stopped: bool) -> TrayState {
    if sessions > 0 {
        TrayState::Connected
    } else if !window_open {
        TrayState::Closed
    } else if stopped {
        TrayState::Stopped
    } else if !online {
        TrayState::Offline
    } else {
        TrayState::Ready
    }
}

/// Windows keeps 127 characters of a tooltip; each of these is shorter.
pub fn tray_tooltip(state: TrayState) -> &'static str {
    match state {
        TrayState::Closed => "دلفین کانکت بسته است؛ کسی نمی‌تواند وصل شود",
        TrayState::Ready => "دلفین کانکت در دسترس است؛ کارشناس دلفین با اجازه‌ی پورتال وصل می‌شود",
        TrayState::Connected => "دلفین کانکت: کارشناس دلفین وصل است",
        TrayState::Offline => "دلفین کانکت: اینترنت یا سرور دلفین در دسترس نیست",
        TrayState::Stopped => "دلفین کانکت: اشتراک متوقف است؛ کسی نمی‌تواند وصل شود",
    }
}

/// The dot on the icon (DD-47): green ready, blue connected (the brand azure), grey no internet or sharing stopped.
pub fn tray_colour(state: TrayState) -> Option<[u8; 3]> {
    match state {
        TrayState::Closed => None,
        TrayState::Ready => Some([0x16, 0xA3, 0x4A]),
        TrayState::Connected => Some([0x14, 0x62, 0xE0]),
        TrayState::Offline | TrayState::Stopped => Some([0x8A, 0x94, 0xA6]),
    }
}

/// Visible only while somebody could be connected (ADR-0016: "visible while available").
pub fn tray_visible(state: TrayState) -> bool {
    state != TrayState::Closed
}

/// A portable app has no service: once its window process is gone, nothing hosts the server and the tray it started
/// ends too. The installed app's tray (started at sign-in by upstream's Startup shortcut) stays, hidden.
pub fn tray_should_exit(installed: bool, window_open: bool) -> bool {
    !installed && !window_open
}

pub const TRAY_OPEN: &str = "باز کردن";
pub const TRAY_QUIT: &str = "بستن کامل";

/// The PNG frame of an .ico drawn for `want` pixels (offset, length): the exact size, else the next larger, else the
/// largest. The tray asks Windows for its icon size (16 px at 100 %, 20 at 125 %, 24 at 150 %) so the hand-drawn small
/// frames are shown instead of the 256 px one shrunk. Only PNG frames (dolphin/brand.py writes nothing else).
#[cfg_attr(not(all(windows, feature = "flutter")), allow(dead_code))]
pub fn ico_frame(ico: &[u8], want: u32) -> Option<(usize, usize)> {
    const PNG: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a];
    if ico.len() < 6 || ico[0..4] != [0, 0, 1, 0] {
        return None;
    }
    let count = u16::from_le_bytes([ico[4], ico[5]]) as usize;
    let mut frames = Vec::new();
    for i in 0..count {
        let e = 6 + 16 * i;
        let Some(entry) = ico.get(e..e + 16) else { break };
        let side = if entry[0] == 0 { 256 } else { entry[0] as u32 };
        let len = u32::from_le_bytes([entry[8], entry[9], entry[10], entry[11]]) as usize;
        let off = u32::from_le_bytes([entry[12], entry[13], entry[14], entry[15]]) as usize;
        match ico.get(off..off.saturating_add(len)) {
            Some(data) if data.len() >= 8 && data[..8] == PNG => frames.push((side, off, len)),
            _ => {}
        }
    }
    let exact_or_larger = frames.iter().filter(|f| f.0 >= want).min_by_key(|f| f.0);
    exact_or_larger.or_else(|| frames.iter().max_by_key(|f| f.0)).map(|f| (f.1, f.2))
}

/// Paints a dot with a white ring in the icon's lower-left corner (RGBA, row-major). The lower-left, because Windows
/// draws nothing there and the mark's own shape sits top-right. Sizes from 16 px up.
pub fn badge(rgba: &mut [u8], width: u32, height: u32, colour: [u8; 3]) {
    let (w, h) = (width as i64, height as i64);
    if w <= 0 || h <= 0 || rgba.len() < (w * h * 4) as usize {
        return;
    }
    let side = w.min(h);
    let r = (side * 30 / 100).max(3); // radius of the whole dot, ring included
    let ring = (r / 4).max(1);
    let (cx, cy) = (r, h - r); // centre, in doubled coordinates below for pixel centres
    for y in (h - 2 * r).max(0)..h {
        for x in 0..(2 * r).min(w) {
            // Distance from the pixel centre, doubled to stay in integers.
            let dx = 2 * x + 1 - 2 * cx;
            let dy = 2 * y + 1 - 2 * cy;
            let d2 = dx * dx + dy * dy;
            let i = ((y * w + x) * 4) as usize;
            if d2 <= (2 * (r - ring)) * (2 * (r - ring)) {
                rgba[i..i + 4].copy_from_slice(&[colour[0], colour[1], colour[2], 255]);
            } else if d2 <= (2 * r) * (2 * r) {
                rgba[i..i + 4].copy_from_slice(&[255, 255, 255, 255]);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_way_transfer_turns_upstreams_options_on_only_while_the_switch_shows() {
        // Hidden (and the default, and anything unreadable): upstream's own value stands.
        for raw in ["", "-", "{}", "not json", r#"{"one-way-transfer":"hidden"}"#, r#"{"one-way-transfer":"loud"}"#] {
            assert_eq!(switch_mode(raw, SWITCH_ONE_WAY_TRANSFER), SwitchMode::Hidden, "{raw}");
            assert_eq!(builtin_override(ONE_WAY_FILE_TRANSFER, raw), None, "{raw}");
            assert_eq!(builtin_override(ONE_WAY_CLIPBOARD, raw), None, "{raw}");
        }
        for raw in [r#"{"one-way-transfer":"available"}"#, r#"{"one-way-transfer":"forced"}"#] {
            assert_eq!(builtin_override(ONE_WAY_FILE_TRANSFER, raw), Some("Y"), "{raw}");
            assert_eq!(builtin_override(ONE_WAY_CLIPBOARD, raw), Some("Y"), "{raw}");
            // Other built-in options are never touched.
            assert_eq!(builtin_override("hide-tray", raw), None);
            assert_eq!(builtin_override("one-way-file-transfer ", raw), None);
        }
        // The keys are upstream's (libs/base/src/config/keys.rs).
        assert_eq!(ONE_WAY_FILE_TRANSFER, "one-way-file-transfer");
        assert_eq!(ONE_WAY_CLIPBOARD, "one-way-clipboard-redirection");
        assert!(is_one_way_key(ONE_WAY_CLIPBOARD) && !is_one_way_key("lock_after_session_end"));
    }

    #[test]
    fn lock_on_end_adds_to_the_technicians_choice_and_never_removes_it() {
        assert!(!lock_at_end(false, SwitchMode::Hidden)); // the default: as upstream, off
        assert!(lock_at_end(true, SwitchMode::Hidden)); // the technician's own toggle still works
        assert!(lock_at_end(false, SwitchMode::Available));
        assert!(lock_at_end(false, SwitchMode::Forced));
        assert!(!lock_at_end_by(false, ""));
        assert!(!lock_at_end_by(false, r#"{"lock-on-end":"hidden"}"#));
        assert!(lock_at_end_by(false, r#"{"lock-on-end":"forced"}"#));
        assert_eq!(switch_default(SWITCH_LOCK_ON_END), SwitchMode::Hidden);
        assert_eq!(switch_default(SWITCH_ONE_WAY_TRANSFER), SwitchMode::Hidden);
    }

    #[test]
    fn switches_read_like_the_dart_side() {
        let raw = r#"{"share-toggle":"forced","stay-in-tray":"loud","receive-folder":"hidden","n":1,"o":{"a":"}"}}"#;
        assert_eq!(switch_mode(raw, SWITCH_SHARE_TOGGLE), SwitchMode::Forced);
        assert_eq!(switch_mode(raw, SWITCH_STAY_IN_TRAY), SwitchMode::Available); // bad mode: default
        assert_eq!(switch_mode(raw, SWITCH_RECEIVE_FOLDER), SwitchMode::Hidden);
        for bad in ["", "-", "not json", "[1,2]", "{", r#"{"share-toggle":"forced""#, r#"{"a":"b"} x"#] {
            assert_eq!(switch_mode(bad, SWITCH_SHARE_TOGGLE), SwitchMode::Available, "{bad}");
            assert_eq!(switch_mode(bad, "direct-route"), SwitchMode::Forced, "{bad}");
        }
        assert_eq!(switch_mode("{}", "never-heard-of"), SwitchMode::Hidden);
        assert_eq!(switch_mode(" { \"stay-in-tray\" : \"hidden\" } ", SWITCH_STAY_IN_TRAY), SwitchMode::Hidden);
        assert_eq!(switch_mode(r#"{"stay-in-tray":"hidden","stay-in-tray":"forced"}"#, SWITCH_STAY_IN_TRAY), SwitchMode::Forced);
        assert_eq!(switch_mode(r#"{"x":"a\"b","stay-in-tray":"forced"}"#, SWITCH_STAY_IN_TRAY), SwitchMode::Forced);
        assert_eq!(switch_mode(r#"{"st\u0061y-in-tray":"forced"}"#, SWITCH_STAY_IN_TRAY), SwitchMode::Forced);
        assert_eq!(switch_mode(r#"{"a":[1,{"b":"]"}],"receive-folder":"forced"}"#, SWITCH_RECEIVE_FOLDER), SwitchMode::Forced);
    }

    #[test]
    fn stopped_sharing_refuses_only_while_the_control_exists() {
        assert!(sharing_stopped(SwitchMode::Available, "Y"));
        assert!(sharing_stopped(SwitchMode::Forced, "Y"));
        assert!(!sharing_stopped(SwitchMode::Hidden, "Y")); // the control is gone: an old Y must not lock the PC
        assert!(!sharing_stopped(SwitchMode::Available, ""));
        assert!(!sharing_stopped(SwitchMode::Available, "N"));
        assert_eq!(heartbeat_share(true), "stopped");
        assert_eq!(heartbeat_share(false), "on");
    }

    #[test]
    fn the_remote_printer_is_off_unless_the_portal_turns_it_on() {
        assert_eq!(switch_default(SWITCH_REMOTE_PRINTER), SwitchMode::Hidden); // as kSwitchDefaults in switches.dart
        assert_eq!(switch_mode("", SWITCH_REMOTE_PRINTER), SwitchMode::Hidden);
        assert!(!printer_forward(SwitchMode::Hidden, true));
        assert!(!printer_forward(SwitchMode::Hidden, false));
        assert!(printer_forward(SwitchMode::Available, true));
        assert!(!printer_forward(SwitchMode::Available, false));
        assert!(printer_forward(SwitchMode::Forced, false));
        let raw = r#"{"remote-printer":"available"}"#;
        assert!(printer_forward(switch_mode(raw, SWITCH_REMOTE_PRINTER), true));
    }

    #[test]
    fn sessions_start_the_printer_poll_only_when_printing_can_happen() {
        assert!(!printer_service_wanted(switch_mode("", SWITCH_REMOTE_PRINTER)));
        assert!(!printer_service_wanted(SwitchMode::Hidden));
        assert!(printer_service_wanted(SwitchMode::Available));
        assert!(printer_service_wanted(SwitchMode::Forced));
    }

    #[test]
    fn the_customer_sound_is_offered_unless_the_portal_hides_it() {
        assert_eq!(switch_default(SWITCH_REMOTE_SOUND), SwitchMode::Available); // as kSwitchDefaults in switches.dart
        assert!(sound_offered_by(""));
        assert!(sound_offered_by("-"));
        assert!(sound_offered_by(r#"{"remote-sound":"available"}"#));
        assert!(sound_offered_by(r#"{"remote-sound":"forced"}"#));
        assert!(!sound_offered_by(r#"{"remote-sound":"hidden"}"#));
        assert!(sound_offered_by(r#"{"remote-printer":"hidden"}"#));
        assert!(!sound_offered(SwitchMode::Hidden));
        assert!(sound_offered(SwitchMode::Available));
        assert!(sound_offered(SwitchMode::Forced));
    }

    #[test]
    fn every_remote_desktop_session_starts_with_the_sound_off() {
        assert!(session_starts_muted(true));
        assert!(!session_starts_muted(false));
    }

    #[test]
    fn the_receive_folder_is_under_downloads() {
        let home = Path::new("C:\\Users\\Ali");
        let d = receive_dir(home);
        assert!(d.ends_with(Path::new("Downloads").join(RECEIVE_FOLDER_NAME)));
        assert!(d.starts_with(home));
        assert!(opens_receive_dir(SwitchMode::Available));
        assert!(opens_receive_dir(SwitchMode::Forced));
        assert!(!opens_receive_dir(SwitchMode::Hidden));
        assert_eq!(login_dir(SwitchMode::Forced, "D:\\old"), "");
        assert_eq!(login_dir(SwitchMode::Available, "D:\\old"), "D:\\old");
        assert_eq!(login_dir(SwitchMode::Hidden, "D:\\old"), "D:\\old");
    }

    #[test]
    fn a_forced_folder_takes_writes_only_inside_it() {
        let base = Path::new("/home/ali/Downloads/rx");
        let f = SwitchMode::Forced;
        assert!(write_allowed(f, base, Path::new("/home/ali/Downloads/rx/a.txt"), false));
        assert!(write_allowed(f, base, Path::new("/home/ali/Downloads/rx/sub/b.txt"), false));
        assert!(!write_allowed(f, base, base, false)); // the folder itself is not a new file in it
        assert!(!write_allowed(f, base, Path::new("/home/ali/Downloads/rx2/a.txt"), false)); // a sibling with the same prefix
        assert!(!write_allowed(f, base, Path::new("/home/ali/Downloads/rx/../x.txt"), false));
        assert!(!write_allowed(f, base, Path::new("/etc/passwd"), false));
        assert!(!write_allowed(f, base, Path::new("/home/ali/downloads/RX/a.txt"), false));
        assert!(write_allowed(f, base, Path::new("/home/ali/downloads/RX/a.txt"), true)); // Windows: no case
        assert!(write_allowed(SwitchMode::Available, base, Path::new("/etc/x"), false));
        assert!(write_allowed(SwitchMode::Hidden, base, Path::new("/etc/x"), false));
    }

    #[test]
    fn the_tray_follows_the_state() {
        assert_eq!(tray_state(true, true, 0, false), TrayState::Ready);
        assert_eq!(tray_state(true, false, 0, false), TrayState::Offline);
        assert_eq!(tray_state(true, true, 0, true), TrayState::Stopped);
        assert_eq!(tray_state(true, false, 0, true), TrayState::Stopped);
        assert_eq!(tray_state(false, true, 0, false), TrayState::Closed);
        assert_eq!(tray_state(true, true, 2, true), TrayState::Connected);
        assert_eq!(tray_state(false, true, 1, false), TrayState::Connected); // installed: a session can outlive it
        assert!(!tray_visible(TrayState::Closed));
        assert!(tray_visible(TrayState::Ready));
        assert_eq!(tray_colour(TrayState::Closed), None);
        assert_ne!(tray_colour(TrayState::Ready), tray_colour(TrayState::Connected));
        assert_ne!(tray_colour(TrayState::Ready), tray_colour(TrayState::Offline));
        for s in [TrayState::Closed, TrayState::Ready, TrayState::Connected, TrayState::Offline, TrayState::Stopped] {
            let t = tray_tooltip(s);
            assert!(t.starts_with("دلفین کانکت"), "{t}");
            assert!(t.encode_utf16().count() < 128, "{t}");
        }
        assert!(tray_should_exit(false, false));
        assert!(!tray_should_exit(false, true));
        assert!(!tray_should_exit(true, false));
    }

    #[test]
    fn the_badge_paints_the_lower_left_corner_only() {
        let (w, h) = (32u32, 32u32);
        let mut px = vec![0u8; (w * h * 4) as usize];
        badge(&mut px, w, h, [1, 2, 3]);
        let at = |x: u32, y: u32| &px[((y * w + x) * 4) as usize..((y * w + x) * 4 + 4) as usize];
        let r = 32 * 30 / 100;
        assert_eq!(at(r as u32, (32 - r) as u32), &[1, 2, 3, 255]); // the centre
        assert_eq!(at(0, (32 - r) as u32), &[255, 255, 255, 255]); // the ring at its edge
        assert_eq!(at(31, 0), &[0, 0, 0, 0]); // the opposite corner is untouched
        assert_eq!(at(31, 31), &[0, 0, 0, 0]);
        let mut small = vec![0u8; 16 * 16 * 4];
        badge(&mut small, 16, 16, [9, 9, 9]);
        assert!(small.chunks(4).any(|p| p == [9, 9, 9, 255]));
        let mut short = vec![0u8; 10];
        badge(&mut short, 16, 16, [9, 9, 9]); // a wrong buffer is left alone
        assert!(short.iter().all(|b| *b == 0));
    }
    fn toy_ico(sizes: &[u32]) -> Vec<u8> {
        // header + entries + one tiny "PNG" per frame (signature + the size byte), as Pillow writes them
        let mut out = vec![0, 0, 1, 0, sizes.len() as u8, 0];
        let mut offset = 6 + 16 * sizes.len() as u32;
        let mut data = Vec::new();
        for &s in sizes {
            let frame: Vec<u8> = [0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a, s as u8].to_vec();
            out.extend_from_slice(&[(s % 256) as u8, (s % 256) as u8, 0, 0, 1, 0, 32, 0]);
            out.extend_from_slice(&(frame.len() as u32).to_le_bytes());
            out.extend_from_slice(&offset.to_le_bytes());
            offset += frame.len() as u32;
            data.extend(frame);
        }
        out.extend(data);
        out
    }

    #[test]
    fn the_tray_takes_the_frame_drawn_for_its_size() {
        let ico = toy_ico(&[16, 20, 24, 32, 256]);
        let pick = |want| ico_frame(&ico, want).map(|(o, l)| ico[o + l - 1]);
        assert_eq!(pick(16), Some(16)); // 100 % scaling
        assert_eq!(pick(20), Some(20)); // 125 %
        assert_eq!(pick(24), Some(24)); // 150 %
        assert_eq!(pick(28), Some(32)); // no exact frame: the next larger one
        assert_eq!(pick(300), Some(0)); // larger than all: the largest (256 is stored as 0)
        assert_eq!(ico_frame(&[1, 2, 3], 16), None);
        let mut broken = ico.clone();
        broken[6 + 8..6 + 12].copy_from_slice(&9999u32.to_le_bytes()); // a frame past the end
        assert_eq!(ico_frame(&broken, 16).map(|(o, l)| broken[o + l - 1]), Some(20));
    }

}
