//! Dolphin Connect, Plan 19 (D1–D2): «ارائه دمو», the customer watches the technician's screen. The rules, states and
//! texts, standard library only, so CI tests them alone (`rustc --edition 2021 --test src/dolphin_demo_core.rs`). The
//! app side is src/dolphin_demo.rs; the hooks are in src/server/connection.rs, src/rendezvous_mediator.rs,
//! src/ui_session_interface.rs, src/flutter_ffi.rs, src/ui_cm_interface.rs and src/lib.rs, each marked
//! `Dolphin Connect (demo)`.
//!
//! Built on upstream's switch sides, which already lets an incoming-only app connect back to the peer that asked, with
//! a one-time uuid both ends check (`insert_pending_switch_sides_uuid`, `is_switch_sides_back`, `SwitchSidesResponse`):
//! 1. The technician's session (an ordinary, portal-authorized connection to the customer's PC) sends the existing
//!    `Misc::PluginRequest` [`REQUEST_ID`] with a fresh uuid. Its own app starts a [`DemoBook`] wait and registers with
//!    our server for at most [`WAIT_SECS`], the only time an outgoing-only app can be reached.
//! 2. The customer's PC asks first ([`decide`], the window's «دیدن» / «نه», [`ASK_SECS`]); every answer goes back as the
//!    existing `MessageBox` [`ANSWER_MSGTYPE`]. On «دیدن» it does what upstream's switch sides does: it marks the uuid as
//!    pending, starts `--connect <technician> --switch_uuid <uuid>` and ends the first connection.
//! 3. The technician's app takes exactly one incoming connection ([`pre_login`], [`DemoBook::claim`]): a switch-back
//!    login from that customer's ID with that uuid, once, inside the wait. Any password login is refused before a
//!    password is read. The demo connection is view only ([`inbound_allowed`]): no keyboard, mouse, clipboard, files,
//!    sound or control, and the technician's other screens only when he chose «همه‌ی صفحه‌های من».
//!
//! Consent (ADR-0015, ADR-0016) is unchanged and never shortened: the first connection is authorized as usual (Accept,
//! one-time code or the fixed password), and the customer always presses «دیدن» before anything is shown.

// The x86 (Sciter) customer build has no demo: the technician's side is unused there.
#![cfg_attr(not(feature = "flutter"), allow(dead_code))]

/// `PluginRequest.id` of the technician's request; the content is the uuid as text ([`parse_uuid`]).
pub const REQUEST_ID: &str = "dolphin-demo";
/// `MessageBox.msgtype` of every answer; `title` is [`Answer::code`], `text` the Persian line.
pub const ANSWER_MSGTYPE: &str = "dolphin-demo";
/// `platform_additions` key of the customer PC's login answer: true where the demo can be shown (the Flutter build),
/// false on the x86 (Sciter) build of Windows 7/8; an older app says nothing.
pub const PLATFORM_ADDITION: &str = "dolphin_demo";
/// `platform_additions` key of the technician PC's answer to the demo login: [`screens_value`], so the customer's
/// window offers a screen picker only when the technician allowed all his screens.
pub const PLATFORM_SCREENS: &str = "dolphin_demo_screens";
/// Connection → customer window (`ipc::Data::SwitchPermission` names): show (`true`) or hide the prompt.
pub const CM_ASK: &str = "dolphin-demo-ask";
/// Customer window → connection: «دیدن» (`true`) or «نه» (`false`).
pub const CM_ANSWER: &str = "dolphin-demo-answer";
/// Technician's session (`session_set_common` key): start the demo; the value is [`screens_value`].
pub const SESSION_START: &str = "dolphin-demo";
/// Technician's session: forget the wait (the customer refused, or the technician gave up).
pub const SESSION_CANCEL: &str = "dolphin-demo-cancel";
/// Technician's dashboard (`main_set_common`): the next session to this PC is a demo; `<screens>:<peer id>`.
/// The session window takes it once (`session_get_common`), right when it opens.
pub const INTENT_KEY: &str = "dolphin-demo-intent";
/// The connection audit's `action` the customer PC posts when the customer pressed «دیدن» (portal: engine.demo_viewed).
pub const AUDIT_ACTION: &str = "demo";
/// Why the customer PC ends the first connection after an answer; a word the technician app's quiet retry skips.
pub const CLOSE_REASON: &str = "Closed manually for the Dolphin demo";
/// How long the customer's prompt waits for «دیدن» / «نه».
pub const ASK_SECS: u64 = 60;
/// How long the technician's app waits for the customer's PC to connect back, from the request: the prompt, then the
/// start of the customer's demo window and its connection.
pub const WAIT_SECS: u64 = ASK_SECS + 30;
/// How long the dashboard's intent waits for the session window to open.
pub const INTENT_SECS: u64 = 30;

/// Whether the technician allowed all his screens («همه‌ی صفحه‌های من»): the session value and the platform addition.
pub fn screens_value(all: bool) -> &'static str {
    if all {
        "all"
    } else {
        "primary"
    }
}

/// The opposite of [`screens_value`]; `None` for anything else (nothing is sent).
pub fn screens_from(value: &str) -> Option<bool> {
    match value {
        "all" => Some(true),
        "primary" => Some(false),
        _ => None,
    }
}

/// The request's uuid in its canonical lower-case text, or `None` unless it is exactly a 36-character uuid.
pub fn parse_uuid(content: &[u8]) -> Option<String> {
    let text = std::str::from_utf8(content).ok()?;
    if text.len() != 36 {
        return None;
    }
    for (i, c) in text.chars().enumerate() {
        let ok = if matches!(i, 8 | 13 | 18 | 23) { c == '-' } else { c.is_ascii_hexdigit() };
        if !ok {
            return None;
        }
    }
    Some(text.to_ascii_lowercase())
}

/// Whether a `PluginRequest` id is this request (the pause gate treats it as control, not as typing).
pub fn is_request(id: &str) -> bool {
    id == REQUEST_ID
}

/// The dashboard's intent `<screens>:<peer id>`: the peer and whether all screens; `None` when malformed.
pub fn parse_intent(value: &str) -> Option<(String, bool)> {
    let (screens, peer) = value.split_once(':')?;
    let all = screens_from(screens)?;
    let peer = peer.trim();
    if peer.is_empty() {
        return None;
    }
    Some((peer.to_owned(), all))
}

/// What the customer's PC knows when a request comes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Scene {
    /// The customer window can show the prompt and the demo window (the Flutter build; the x86 Sciter one cannot).
    pub ui: bool,
    /// The customer paused the session (DD-46).
    pub paused: bool,
    /// A prompt or a Safe Mode notice is already on the customer's window.
    pub busy: bool,
    /// The customer's window has this connection (its Login reached it), so the prompt can show.
    pub window: bool,
}

/// Why the customer's PC does not ask.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refusal {
    Unsupported,
    Paused,
    Busy,
    NoWindow,
}

/// Ask the customer, or why not. Only for an authorised remote-control session (checked by the caller).
pub fn decide(s: &Scene) -> Result<(), Refusal> {
    if !s.ui {
        return Err(Refusal::Unsupported);
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

/// Whether the prompt asked at `asked_ms` has run out.
pub fn ask_expired(asked_ms: u64, now_ms: u64) -> bool {
    now_ms.saturating_sub(asked_ms) >= ASK_SECS * 1000
}

/// What the customer's PC tells the technician.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Answer {
    /// The prompt is on the customer's screen.
    Asking,
    /// «دیدن»: the customer's PC connects back.
    Accepted,
    /// «نه».
    Refused,
    /// Nobody answered within [`ASK_SECS`].
    NoAnswer,
    /// «دیدن», but the demo window could not be started on the customer's PC.
    NotStarted,
    /// Not asked.
    NotAsked(Refusal),
    /// Said by the technician's own app: a demo is already running.
    Running,
}

impl Answer {
    pub fn code(self) -> &'static str {
        match self {
            Answer::Asking => "asking",
            Answer::Accepted => "accepted",
            Answer::Refused => "refused",
            Answer::NoAnswer => "no-answer",
            Answer::NotStarted => "not-started",
            Answer::NotAsked(Refusal::Unsupported) => "unsupported",
            Answer::NotAsked(Refusal::Paused) => "paused",
            Answer::NotAsked(Refusal::Busy) => "busy",
            Answer::NotAsked(Refusal::NoWindow) => "no-window",
            Answer::Running => "running",
        }
    }

    /// The technician's line. Persian, no English, the support phone never needed.
    pub fn text(self) -> &'static str {
        match self {
            Answer::Asking => "از مشتری پرسیده شد؛ منتظر «دیدن» است.",
            Answer::Accepted => "مشتری «دیدن» را زد؛ رایانه‌ی مشتری به رایانه‌ی شما وصل می‌شود.",
            Answer::Refused => "مشتری دمو را نپذیرفت.",
            Answer::NoAnswer => "مشتری در یک دقیقه جواب نداد.",
            Answer::NotStarted => "پنجره‌ی دمو روی رایانه‌ی مشتری باز نشد؛ دوباره امتحان کنید.",
            Answer::NotAsked(Refusal::Unsupported) => "دمو برای این رایانه (ویندوز ۷/۸) در دسترس نیست",
            Answer::NotAsked(Refusal::Paused) => "مشتری جلسه را مکث کرده است؛ پس از «ادامه» دوباره امتحان کنید.",
            Answer::NotAsked(Refusal::Busy) => "پیام دیگری روی صفحه‌ی مشتری باز است؛ کمی بعد دوباره امتحان کنید.",
            Answer::NotAsked(Refusal::NoWindow) => "پنجره‌ی دلفین کانکت مشتری هنوز آماده نیست؛ چند ثانیه بعد دوباره امتحان کنید.",
            Answer::Running => "یک دمو در جریان است؛ اول آن را تمام کنید.",
        }
    }

    /// Whether the customer's PC ends the first connection after sending this: a demo never turns into a control
    /// session. «دیدن» hands over to the demo; «نه» and no answer end it too.
    pub fn ends_first_connection(self) -> bool {
        matches!(self, Answer::Accepted | Answer::Refused | Answer::NoAnswer)
    }
}

/// The technician app's one demo at a time.
#[derive(Debug, Clone, PartialEq, Eq)]
enum State {
    Idle,
    /// Waiting for the customer's PC `peer` to connect back with `uuid`, since `since_ms`.
    Waiting { peer: String, uuid: String, all: bool, since_ms: u64 },
    /// The demo connection is in.
    Running,
}

/// The technician app's demo: who may connect back, with what, until when. One process-wide book.
#[derive(Debug)]
pub struct DemoBook {
    state: State,
}

impl DemoBook {
    pub const fn new() -> Self {
        DemoBook { state: State::Idle }
    }

    /// A new demo request to `peer`. Replaces an earlier wait (that request is dead); refused while a demo runs.
    pub fn begin(&mut self, peer: &str, uuid: &str, all: bool, now_ms: u64) -> bool {
        if self.state == State::Running || peer.is_empty() {
            return false;
        }
        let Some(uuid) = parse_uuid(uuid.as_bytes()) else {
            return false;
        };
        self.state = State::Waiting { peer: peer.to_owned(), uuid, all, since_ms: now_ms };
        true
    }

    /// Whether the app should be reachable now: only while a wait is fresh. An old wait is forgotten here.
    pub fn listening(&mut self, now_ms: u64) -> bool {
        self.expire(now_ms);
        matches!(self.state, State::Waiting { .. })
    }

    /// An incoming switch-back login from `peer` with `uuid`: `Some(all screens)` once, for the awaited peer and uuid
    /// inside the wait; `None` for anything else, which leaves the wait as it is (a wrong guess does not end it).
    pub fn claim(&mut self, peer: &str, uuid: &str, now_ms: u64) -> Option<bool> {
        self.expire(now_ms);
        let State::Waiting { peer: p, uuid: u, all, .. } = &self.state else {
            return None;
        };
        if p != peer || parse_uuid(uuid.as_bytes()).as_deref() != Some(u.as_str()) {
            return None;
        }
        let all = *all;
        self.state = State::Running;
        Some(all)
    }

    /// The technician's session gave up the wait for `peer` (refused, no answer, cancelled).
    pub fn cancel(&mut self, peer: &str) {
        if matches!(&self.state, State::Waiting { peer: p, .. } if p == peer) {
            self.state = State::Idle;
        }
    }

    /// The demo connection closed.
    pub fn ended(&mut self) {
        if self.state == State::Running {
            self.state = State::Idle;
        }
    }

    #[cfg_attr(not(test), allow(dead_code))]
    pub fn running(&self) -> bool {
        self.state == State::Running
    }

    fn expire(&mut self, now_ms: u64) {
        if let State::Waiting { since_ms, .. } = self.state {
            if now_ms.saturating_sub(since_ms) >= WAIT_SECS * 1000 {
                self.state = State::Idle;
            }
        }
    }
}

/// An incoming message before login, as the gate sees it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreLogin {
    /// `LoginRequest`: a password, a one-time code, a file transfer, a terminal, a port forward.
    Login,
    /// `SwitchSidesResponse`: upstream's switch-back login, with a uuid and no password.
    SwitchBack,
    /// Anything else (upstream acts on nothing else before login).
    Other,
}

/// What the gate does with it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Gate {
    /// Upstream's handling, unchanged.
    Pass,
    /// Refused and closed, before any password or approval is looked at.
    Refuse,
    /// Only a [`DemoBook::claim`] lets it in; otherwise refused and closed.
    Claim,
}

/// The technician app (outgoing-only) is never logged into: the only way in is the demo's switch-back. Every other app
/// keeps upstream's handling.
pub fn pre_login(outgoing_only: bool, kind: PreLogin) -> Gate {
    if !outgoing_only {
        return Gate::Pass;
    }
    match kind {
        PreLogin::Login => Gate::Refuse,
        PreLogin::SwitchBack => Gate::Claim,
        PreLogin::Other => Gate::Pass,
    }
}

/// A message from the customer's demo window, as the view-only gate sees it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Inbound {
    /// The connection's own upkeep: delay tests, a repeated login, the close.
    Upkeep,
    /// Asking for a fresh picture, saying a frame arrived, the codecs it can decode.
    Picture,
    /// Changing which of the technician's screens is shown.
    Display,
    /// Everything else: input, clipboard, files, sound, chat, options, resolution, virtual displays, restart, plugins.
    Other,
}

/// Whether a demo connection may act on it. Nothing but watching: the screens beyond the first only when the
/// technician allowed all of them.
pub fn inbound_allowed(kind: Inbound, all_screens: bool) -> bool {
    match kind {
        Inbound::Upkeep | Inbound::Picture => true,
        Inbound::Display => all_screens,
        Inbound::Other => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const U: &str = "6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b";
    const V: &str = "00000000-0000-4000-8000-000000000000";

    #[test]
    fn screens_round_trip_and_nothing_else_parses() {
        assert_eq!(screens_from(screens_value(true)), Some(true));
        assert_eq!(screens_from(screens_value(false)), Some(false));
        assert_eq!(screens_from("ALL"), None);
        assert_eq!(screens_from(""), None);
    }

    #[test]
    fn only_a_real_uuid_is_taken_and_in_lower_case() {
        assert_eq!(parse_uuid(U.as_bytes()).as_deref(), Some(U));
        assert_eq!(parse_uuid(U.to_uppercase().as_bytes()).as_deref(), Some(U));
        assert_eq!(parse_uuid(b""), None);
        assert_eq!(parse_uuid(&U.as_bytes()[1..]), None);
        assert_eq!(parse_uuid(format!("{U} ").as_bytes()), None);
        assert_eq!(parse_uuid(U.replace('-', "x").as_bytes()), None);
        assert_eq!(parse_uuid(U.replacen('6', "g", 1).as_bytes()), None);
        assert_eq!(parse_uuid(&[0xff; 36]), None);
    }

    #[test]
    fn the_intent_names_a_peer_and_its_screens() {
        assert_eq!(parse_intent("all:123456789"), Some(("123456789".to_owned(), true)));
        assert_eq!(parse_intent("primary:987"), Some(("987".to_owned(), false)));
        assert_eq!(parse_intent("primary:"), None);
        assert_eq!(parse_intent("every:1"), None);
        assert_eq!(parse_intent("123"), None);
    }

    fn scene() -> Scene {
        Scene { ui: true, paused: false, busy: false, window: true }
    }

    #[test]
    fn the_customer_is_asked_only_where_the_demo_can_show() {
        assert_eq!(decide(&scene()), Ok(()));
        assert_eq!(decide(&Scene { ui: false, ..scene() }), Err(Refusal::Unsupported));
        assert_eq!(decide(&Scene { paused: true, ..scene() }), Err(Refusal::Paused));
        assert_eq!(decide(&Scene { busy: true, ..scene() }), Err(Refusal::Busy));
        assert_eq!(decide(&Scene { window: false, ..scene() }), Err(Refusal::NoWindow));
        // The x86 build says so even when it is also paused or busy: the technician learns the one thing that lasts.
        assert_eq!(decide(&Scene { ui: false, paused: true, busy: true, window: false }), Err(Refusal::Unsupported));
    }

    #[test]
    fn the_prompt_runs_out_after_a_minute() {
        assert!(!ask_expired(1_000, 1_000 + ASK_SECS * 1000 - 1));
        assert!(ask_expired(1_000, 1_000 + ASK_SECS * 1000));
        assert!(!ask_expired(5_000, 1_000)); // a clock that went back is not "expired"
    }

    #[test]
    fn answers_have_distinct_codes_and_persian_texts() {
        let all = [
            Answer::Asking,
            Answer::Accepted,
            Answer::Refused,
            Answer::NoAnswer,
            Answer::NotStarted,
            Answer::NotAsked(Refusal::Unsupported),
            Answer::NotAsked(Refusal::Paused),
            Answer::NotAsked(Refusal::Busy),
            Answer::NotAsked(Refusal::NoWindow),
            Answer::Running,
        ];
        let mut codes: Vec<_> = all.iter().map(|a| a.code()).collect();
        codes.sort();
        codes.dedup();
        assert_eq!(codes.len(), all.len());
        for a in all {
            assert!(a.text().chars().any(|c| ('\u{0600}'..='\u{06FF}').contains(&c)), "{}", a.code());
            assert!(!a.text().chars().any(|c| c.is_ascii_alphabetic()), "{}", a.code());
        }
        assert_eq!(Answer::NotAsked(Refusal::Unsupported).text(), "دمو برای این رایانه (ویندوز ۷/۸) در دسترس نیست");
    }

    #[test]
    fn a_demo_never_leaves_a_control_session_behind() {
        assert!(Answer::Accepted.ends_first_connection());
        assert!(Answer::Refused.ends_first_connection());
        assert!(Answer::NoAnswer.ends_first_connection());
        assert!(!Answer::Asking.ends_first_connection());
        assert!(!Answer::NotStarted.ends_first_connection());
        assert!(!Answer::NotAsked(Refusal::Unsupported).ends_first_connection());
        assert!(!Answer::NotAsked(Refusal::Paused).ends_first_connection());
        // The quiet retry (flutter/lib/dolphin/reconnect.dart) skips any close with "manually" in it.
        assert!(CLOSE_REASON.to_lowercase().contains("manually"));
    }

    #[test]
    fn only_the_awaited_peer_with_the_awaited_uuid_gets_in_once() {
        let mut book = DemoBook::new();
        assert!(!book.listening(0));
        assert_eq!(book.claim("111", U, 0), None); // nothing awaited
        assert!(book.begin("111", U, false, 1_000));
        assert!(book.listening(1_000));
        assert_eq!(book.claim("222", U, 2_000), None); // another PC with the right uuid
        assert_eq!(book.claim("111", V, 2_000), None); // the right PC with another uuid
        assert_eq!(book.claim("", U, 2_000), None);
        assert!(book.listening(2_000)); // wrong guesses do not end the wait
        assert_eq!(book.claim("111", &U.to_uppercase(), 3_000), Some(false));
        assert!(book.running());
        assert!(!book.listening(3_000)); // in: no longer reachable
        assert_eq!(book.claim("111", U, 3_000), None); // once
        book.ended();
        assert!(!book.running());
        assert_eq!(book.claim("111", U, 3_000), None);
    }

    #[test]
    fn the_wait_ends_by_itself() {
        let mut book = DemoBook::new();
        assert!(book.begin("111", U, true, 0));
        assert!(book.listening(WAIT_SECS * 1000 - 1));
        assert!(!book.listening(WAIT_SECS * 1000));
        assert_eq!(book.claim("111", U, WAIT_SECS * 1000 - 1), None); // forgotten, not revived
        let mut late = DemoBook::new();
        assert!(late.begin("111", U, true, 0));
        assert_eq!(late.claim("111", U, WAIT_SECS * 1000), None);
        assert!(!late.running());
    }

    #[test]
    fn cancel_ends_only_that_wait_and_a_new_request_replaces_the_old() {
        let mut book = DemoBook::new();
        assert!(book.begin("111", U, true, 0));
        book.cancel("222");
        assert!(book.listening(1));
        book.cancel("111");
        assert!(!book.listening(1));
        assert!(book.begin("111", U, true, 0));
        assert!(book.begin("333", V, false, 10)); // the first request is dead
        assert_eq!(book.claim("111", U, 20), None);
        assert_eq!(book.claim("333", V, 20), Some(false));
    }

    #[test]
    fn one_demo_at_a_time_and_bad_input_starts_nothing() {
        let mut book = DemoBook::new();
        assert!(!book.begin("111", "not-a-uuid", true, 0));
        assert!(!book.begin("", U, true, 0));
        assert!(!book.listening(0));
        assert!(book.begin("111", U, true, 0));
        assert_eq!(book.claim("111", U, 1), Some(true));
        assert!(!book.begin("222", V, true, 2)); // running: refused
        book.cancel("111"); // a cancel does not end a running demo
        assert!(book.running());
        book.ended();
        assert!(book.begin("222", V, true, 3));
    }

    #[test]
    fn the_technician_app_is_never_logged_into() {
        assert_eq!(pre_login(true, PreLogin::Login), Gate::Refuse);
        assert_eq!(pre_login(true, PreLogin::SwitchBack), Gate::Claim);
        assert_eq!(pre_login(true, PreLogin::Other), Gate::Pass);
        for kind in [PreLogin::Login, PreLogin::SwitchBack, PreLogin::Other] {
            assert_eq!(pre_login(false, kind), Gate::Pass); // customer apps: upstream unchanged
        }
    }

    #[test]
    fn a_demo_connection_only_watches() {
        for all in [false, true] {
            assert!(inbound_allowed(Inbound::Upkeep, all));
            assert!(inbound_allowed(Inbound::Picture, all));
            assert!(!inbound_allowed(Inbound::Other, all));
        }
        assert!(!inbound_allowed(Inbound::Display, false));
        assert!(inbound_allowed(Inbound::Display, true));
    }
}
