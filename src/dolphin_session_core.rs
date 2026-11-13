//! Dolphin Connect (Plan 18 Phase 2: DD-46 pause, DD-37 input-off notice, DD-45 live permissions): the rules for the
//! customer's controls during a session, standard library only, so CI tests them alone
//! (`rustc --edition 2021 --test src/dolphin_session_core.rs`). The hooks are in src/server/connection.rs (marked
//! `Dolphin Connect (DD-46)` and so on) and src/ui_cm_interface.rs; the customer's window is
//! flutter/lib/dolphin/connection.dart, the technician's notice flutter/lib/dolphin/permissions.dart.
//!
//! No new network message. Everything rides on messages both apps already speak:
//! - the customer's window asks the connection to pause or resume with the existing CM permission switch
//!   (`ipc::Data::SwitchPermission`, name [`PAUSE_SWITCH`]); the connection tells the window that the technician
//!   blocked the customer's input the same way (name [`INPUT_BLOCKED_NOTICE`]);
//! - the technician hears of a pause through the permission messages he already gets (keyboard, clipboard and files
//!   read as off, so his own toolbar and the permission strip show it) and one `MessageBox` with [`PAUSE_MSGTYPE`] and
//!   [`PAUSED_TITLE`] / [`RESUMED_TITLE`], which the Dolphin technician app shows as «مشتری مکث کرد» over the picture
//!   instead of a dialog (an older app shows it as a plain message).
//!
//! What a pause does on the customer's PC, in the connection itself (not in the window, so a slow or closed window
//! cannot leak a frame): video frames are dropped before they reach the network, and so are sound, the cursor's
//! position and the clipboard; nothing the technician sends that would act on the PC is applied (mouse, keyboard,
//! clipboard, files, screenshots, terminal, restart, elevation, resolution). Test-delay pings and the rest of the
//! session go on as before, so the technician's app does not time out: ADR-0013, no time limit while connected. A
//! paused session that drops (VPN, network) and comes back within [`REMEMBER_MS`] starts paused again
//! ([`PauseBook`]), so a reconnect cannot show the screen the customer was hiding.

/// CM permission name for pause (`enabled` = paused), both ways over `ipc::Data::SwitchPermission`.
pub const PAUSE_SWITCH: &str = "dolphin_pause";
/// Connection → CM: the technician's "block user input" took effect (`enabled` = blocked).
pub const INPUT_BLOCKED_NOTICE: &str = "dolphin_input_blocked";

/// The `MessageBox` the technician's app reads (flutter/lib/dolphin/permissions.dart `dolphinPauseFromMsgBox`).
pub const PAUSE_MSGTYPE: &str = "dolphin-pause";
pub const PAUSED_TITLE: &str = "dolphin-paused";
pub const RESUMED_TITLE: &str = "dolphin-resumed";
/// What an app that does not know the title shows.
pub const PAUSED_TEXT: &str = "مشتری مکث کرد";
pub const RESUMED_TEXT: &str = "مشتری ادامه داد";
/// A screenshot asked for during a pause gets this instead of a picture.
pub const SCREENSHOT_REFUSED: &str = "مشتری مکث کرده است؛ عکس گرفته نشد.";

/// How long a paused session that dropped is remembered: the same 2 minutes in which it may come back without a new
/// Accept (`SESSION_TIMEOUT` in src/server/connection.rs, owner decision D23).
pub const REMEMBER_MS: u64 = 120_000;

/// What the technician sends, by what it would do on the customer's PC.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Inbound {
    /// Mouse, pointer and keyboard events.
    Input,
    /// Text or file clipboard towards the PC.
    Clipboard,
    /// File actions and the Windows file clipboard.
    Files,
    /// A screenshot request: a picture by another road.
    Screenshot,
    /// Terminal, restart, elevation, change of resolution or virtual display, switching sides.
    Control,
    /// Everything else: pings, acknowledgements, chat, display choice, options (gated on their own).
    Other,
}

/// Whether a message from the technician may act now. While paused only [`Inbound::Other`] passes.
pub fn inbound_allowed(paused: bool, kind: Inbound) -> bool {
    !paused || kind == Inbound::Other
}

/// What the customer's PC sends, by what it shows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outbound {
    Video,
    Audio,
    /// Where the cursor is: where the customer is clicking.
    CursorPosition,
    /// Text or file clipboard towards the technician (a password copied during the pause).
    Clipboard,
    /// Cursor shapes, display changes, permission and control messages, pings.
    Other,
}

/// Whether a message to the technician may leave the PC now. Cursor shapes still go: they are cached by id on the
/// technician's side, and dropping one would leave a wrong cursor after the pause.
pub fn outbound_allowed(paused: bool, kind: Outbound) -> bool {
    !paused || kind == Outbound::Other
}

/// What the technician is told about keyboard and mouse, clipboard and files: the customer's choice, and off for all
/// three during a pause. The customer's choice itself is kept and comes back with «ادامه».
pub fn told_permissions(paused: bool, keyboard: bool, clipboard: bool, file: bool) -> (bool, bool, bool) {
    if paused {
        (false, false, false)
    } else {
        (keyboard, clipboard, file)
    }
}

/// The CM's permission switch obeys upstream's `enable-perm-change-in-accept-window` policy. Switching something off
/// and pausing or resuming always pass: they are the customer's own control (SECURITY.md control 1), and resuming only
/// returns to what the customer had already allowed.
pub fn cm_switch_allowed(policy_allows: bool, name: &str, enabled: bool) -> bool {
    policy_allows || !enabled || name == PAUSE_SWITCH
}

/// Paused sessions by technician ID, so one that drops and comes back within [`REMEMBER_MS`] starts paused. `None`:
/// a paused connection of that technician is still open; `Some(t)`: the last one ended at `t` (ms, [`mono_ms`]).
pub struct PauseBook {
    entries: Vec<(String, Option<u64>)>,
}

impl PauseBook {
    pub const fn new() -> Self {
        Self { entries: Vec::new() }
    }

    fn find(&self, peer: &str) -> Option<usize> {
        self.entries.iter().position(|(p, _)| p == peer)
    }

    /// The customer paused a session of `peer`.
    pub fn paused(&mut self, peer: &str) {
        match self.find(peer) {
            Some(i) => self.entries[i].1 = None,
            None => self.entries.push((peer.to_owned(), None)),
        }
    }

    /// The customer pressed «ادامه»: nothing to carry over.
    pub fn resumed(&mut self, peer: &str) {
        self.entries.retain(|(p, _)| p != peer);
    }

    /// A paused connection of `peer` closed (any reason) at `now`.
    pub fn ended(&mut self, peer: &str, now: u64) {
        if let Some(i) = self.find(peer) {
            self.entries[i].1 = Some(now);
        }
    }

    /// Whether a new session of `peer` starts paused. Forgets what is older than [`REMEMBER_MS`].
    pub fn starts_paused(&mut self, peer: &str, now: u64) -> bool {
        self.entries
            .retain(|(_, ended)| ended.map_or(true, |t| now.saturating_sub(t) < REMEMBER_MS));
        self.find(peer).is_some()
    }
}

/// Milliseconds on a monotonic clock (from the first call), for [`PauseBook`].
pub fn mono_ms() -> u64 {
    use std::sync::OnceLock;
    use std::time::Instant;
    static START: OnceLock<Instant> = OnceLock::new();
    START.get_or_init(Instant::now).elapsed().as_millis() as u64
}

/// The `action` of the connection audit the portal records for «مکث» / «ادامه» (DD-46: pauses are audited).
#[cfg_attr(not(feature = "flutter"), allow(dead_code))]
pub fn pause_audit_action(paused: bool) -> &'static str {
    if paused {
        "pause"
    } else {
        "resume"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pause_lets_nothing_act_on_the_pc() {
        for kind in [Inbound::Input, Inbound::Clipboard, Inbound::Files, Inbound::Screenshot, Inbound::Control] {
            assert!(!inbound_allowed(true, kind), "{:?}", kind);
            assert!(inbound_allowed(false, kind), "{:?}", kind);
        }
        // Pings and acknowledgements keep the session alive (ADR-0013).
        assert!(inbound_allowed(true, Inbound::Other));
    }

    #[test]
    fn a_pause_sends_no_picture_sound_cursor_or_clipboard() {
        for kind in [Outbound::Video, Outbound::Audio, Outbound::CursorPosition, Outbound::Clipboard] {
            assert!(!outbound_allowed(true, kind), "{:?}", kind);
            assert!(outbound_allowed(false, kind), "{:?}", kind);
        }
        assert!(outbound_allowed(true, Outbound::Other));
    }

    #[test]
    fn the_technician_is_told_everything_is_off_while_paused() {
        assert_eq!(told_permissions(true, true, true, true), (false, false, false));
        assert_eq!(told_permissions(false, true, false, true), (true, false, true));
    }

    #[test]
    fn switching_off_and_pausing_always_pass_the_policy() {
        assert!(cm_switch_allowed(false, "keyboard", false));
        assert!(cm_switch_allowed(false, "file", false));
        assert!(!cm_switch_allowed(false, "keyboard", true));
        assert!(cm_switch_allowed(false, PAUSE_SWITCH, true));
        assert!(cm_switch_allowed(false, PAUSE_SWITCH, false));
        assert!(cm_switch_allowed(true, "clipboard", true));
    }

    #[test]
    fn a_paused_session_that_drops_comes_back_paused_for_two_minutes() {
        let mut book = PauseBook::new();
        assert!(!book.starts_paused("287654321", 0));
        book.paused("287654321");
        // Still open: a second window of the same technician starts paused too.
        assert!(book.starts_paused("287654321", 5_000));
        book.ended("287654321", 10_000);
        assert!(book.starts_paused("287654321", 10_000 + REMEMBER_MS - 1));
        assert!(!book.starts_paused("111111111", 10_001));
        // After the window it is forgotten.
        assert!(!book.starts_paused("287654321", 10_000 + REMEMBER_MS));
        assert!(!book.starts_paused("287654321", 0));
    }

    #[test]
    fn resume_forgets_and_a_new_pause_reopens() {
        let mut book = PauseBook::new();
        book.paused("287654321");
        book.resumed("287654321");
        assert!(!book.starts_paused("287654321", 1));
        book.paused("287654321");
        book.ended("287654321", 100);
        book.paused("287654321"); // the session came back paused
        assert!(book.starts_paused("287654321", 100 + REMEMBER_MS * 5));
        // Ending an unpaused technician's session records nothing.
        book.ended("111111111", 100);
        assert!(!book.starts_paused("111111111", 101));
    }

    #[test]
    fn the_clock_does_not_go_back() {
        let a = mono_ms();
        let b = mono_ms();
        assert!(b >= a);
    }

    #[test]
    fn the_names_match_the_dart_side() {
        // flutter/lib/dolphin/session_controls.dart and permissions.dart use the same strings.
        assert_eq!(PAUSE_SWITCH, "dolphin_pause");
        assert_eq!(INPUT_BLOCKED_NOTICE, "dolphin_input_blocked");
        assert_eq!((PAUSE_MSGTYPE, PAUSED_TITLE, RESUMED_TITLE), ("dolphin-pause", "dolphin-paused", "dolphin-resumed"));
    }

    #[test]
    fn a_pause_is_reported_to_the_portal_audit() {
        assert_eq!(pause_audit_action(true), "pause");
        assert_eq!(pause_audit_action(false), "resume");
    }

}
