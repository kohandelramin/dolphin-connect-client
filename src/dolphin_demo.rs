//! Dolphin Connect, Plan 19 (D1–D2): the app side of `src/dolphin_demo_core.rs` («ارائه دمو»), which holds the rules,
//! the states, the texts and their tests. Here: the process-wide demo of the technician app, the dashboard's intent, the
//! messages, and the customer PC's start of its demo window over upstream's switch-back path.
//!
//! The technician app's session and its server (the IPC server, `RendezvousMediator::start_all`, the connections) run
//! in its one process: an outgoing-only app installs no service, so the main process starts the server itself
//! (`start_server(true, ..)`). The book below is therefore seen by the session that starts a demo, by the mediator that
//! registers only while it waits, and by the connection that lets the customer's PC in. Were the server ever in another
//! process, that process would never see a wait and nothing would be accepted: the demo fails closed.

// The x86 (Sciter) customer build has no demo: the technician's side is unused there.
#![cfg_attr(not(feature = "flutter"), allow(dead_code))]

use crate::dolphin_demo_core as rules;
use base::message_proto::*;
use hbb_common::log;
use std::sync::Mutex;

/// The technician app's one demo (src/dolphin_demo_core.rs `DemoBook`).
static BOOK: Mutex<rules::DemoBook> = Mutex::new(rules::DemoBook::new());
/// The dashboard's «ارائه دمو» for the next session window: peer, all screens, when (mono ms).
static INTENT: Mutex<Option<(String, bool, u64)>> = Mutex::new(None);

fn now_ms() -> u64 {
    crate::dolphin_session_core::mono_ms()
}

/// The answer, an existing `MessageBox` the Dolphin technician app shows in its own dialog.
pub fn answer_message(answer: rules::Answer) -> Message {
    let mut msg = Message::new();
    msg.set_message_box(MessageBox {
        msgtype: rules::ANSWER_MSGTYPE.to_owned(),
        title: answer.code().to_owned(),
        text: answer.text().to_owned(),
        link: "".to_owned(),
        ..Default::default()
    });
    msg
}

// ---- the technician's app ----

/// The dashboard asked for a demo to this PC (`main_set_common`, [`rules::INTENT_KEY`]); the session window it opens
/// next takes it with [`take_intent`].
pub fn set_intent(value: &str) {
    let intent = rules::parse_intent(value).map(|(peer, all)| (peer, all, now_ms()));
    if let Ok(mut slot) = INTENT.lock() {
        *slot = intent;
    }
}

/// The session window to `peer`, when it opens: [`rules::screens_value`] once if the dashboard asked for a demo to
/// this PC within [`rules::INTENT_SECS`], otherwise empty (an ordinary session).
pub fn take_intent(peer: &str) -> String {
    let Ok(mut slot) = INTENT.lock() else {
        return String::new();
    };
    // Another PC's intent stays for its own window.
    if matches!(&*slot, Some((p, _, _)) if p != peer) {
        return String::new();
    }
    match slot.take() {
        Some((_, all, at)) if now_ms().saturating_sub(at) < rules::INTENT_SECS * 1000 => {
            rules::screens_value(all).to_owned()
        }
        _ => String::new(),
    }
}

/// What the technician's session does with a `session_set_common` key.
pub enum SessionStep {
    /// Send this to the customer's PC.
    Send(Message),
    /// Show this answer in the session at once, nothing sent.
    Tell(rules::Answer),
    Nothing,
}

/// The technician's session: «ارائه دمو» starts a wait and sends the request; a cancel forgets the wait. `None` when the
/// key is not ours.
pub fn session_request(peer: &str, key: &str, value: &str) -> Option<SessionStep> {
    if key == rules::SESSION_CANCEL {
        if let Ok(mut book) = BOOK.lock() {
            book.cancel(peer);
        }
        return Some(SessionStep::Nothing);
    }
    if key != rules::SESSION_START {
        return None;
    }
    let Some(all) = rules::screens_from(value) else {
        return Some(SessionStep::Nothing);
    };
    let uuid = uuid::Uuid::new_v4().to_string();
    let begun = BOOK.lock().map(|mut book| book.begin(peer, &uuid, all, now_ms())).unwrap_or(false);
    if !begun {
        return Some(SessionStep::Tell(rules::Answer::Running));
    }
    log::info!("Dolphin demo: asked {peer} (all screens: {all})");
    Some(SessionStep::Send(crate::dolphin_panel::plugin_request_message(
        rules::REQUEST_ID,
        uuid.into_bytes(),
    )))
}

/// The mediator registers the technician app with our server only while this is true.
pub fn listening() -> bool {
    BOOK.lock().map(|mut book| book.listening(now_ms())).unwrap_or(false)
}

/// A switch-back login from `peer` with `uuid`: `Some(all screens)` for the one awaited demo, once.
pub fn claim(peer: &str, uuid: &uuid::Uuid) -> Option<bool> {
    BOOK.lock().ok()?.claim(peer, &uuid.to_string(), now_ms())
}

/// The demo connection closed.
pub fn ended() {
    if let Ok(mut book) = BOOK.lock() {
        book.ended();
    }
    log::info!("Dolphin demo: ended");
}

// ---- the customer's PC ----

/// «دیدن»: exactly upstream's switch sides from here on (the `SwitchSidesRequest` arm of src/server/connection.rs): the
/// uuid is marked pending for the technician's ID, so this PC's incoming-only app may connect out to it once, and the
/// demo window starts with `--connect <technician> --switch_uuid <uuid>`.
#[cfg(feature = "flutter")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn launch_view(peer: &str, uuid: &str) -> bool {
    let Ok(parsed) = uuid::Uuid::parse_str(uuid) else {
        return false;
    };
    if !crate::server::insert_pending_switch_sides_uuid(peer.to_owned(), parsed) {
        return false;
    }
    match crate::run_me(vec!["--connect", peer, "--switch_uuid", uuid]) {
        Ok(_) => true,
        Err(err) => {
            log::error!("Dolphin demo: the demo window did not start: {err}");
            false
        }
    }
}

#[cfg(not(all(feature = "flutter", not(any(target_os = "android", target_os = "ios")))))]
pub fn launch_view(_peer: &str, _uuid: &str) -> bool {
    false
}
