//! Dolphin Connect (Plan 14, B6): «با من تماس بگیرید» in the customer window. The form's name and phone go to the
//! portal with this PC's ID and machine UUID (the same pair the heartbeat sends), and the portal opens a request for
//! a technician to call back. Rules and Persian texts: src/dolphin_callback_core.rs. Screen: flutter/lib/dolphin/callback.dart.
use crate::dolphin_callback_core as core;
use hbb_common::log;
use serde_json::{json, Value};
use std::{sync::Mutex, time::Duration};

const TIMEOUT: Duration = Duration::from_secs(15);

lazy_static::lazy_static! {
    static ref STATE: Mutex<Value> = Mutex::new(json!({ "state": "idle" }));
}

/// `{"state": "idle" | "sending" | "done" | "failed", "text": …}` for the screen, which asks twice a second.
pub fn state() -> String {
    STATE.lock().unwrap().to_string()
}

fn set(state: &str, text: &str) {
    *STATE.lock().unwrap() = json!({ "state": state, "text": text });
}

/// Starts sending `{"name", "phone", "note"}` in the background; a second press while one is on its way does nothing.
pub fn start(input: String) {
    let sending = STATE.lock().unwrap().get("state").and_then(|s| s.as_str()) == Some("sending");
    if sending {
        return;
    }
    let v: Value = serde_json::from_str(&input).unwrap_or_default();
    let field = |k: &str| v.get(k).and_then(|s| s.as_str()).unwrap_or("").to_owned();
    let (name, phone, note) = match core::check(&field("name"), &field("phone"), &field("note")) {
        Ok(checked) => checked,
        Err(text) => {
            set("failed", text);
            return;
        }
    };
    set("sending", "");
    std::thread::spawn(move || {
        let (state, text) = match send(&name, &phone, &note) {
            Ok((status, body)) => {
                let (ok, text) = core::answer_text(status, &body);
                (if ok { "done" } else { "failed" }, text)
            }
            Err(e) => {
                log::warn!("Dolphin callback not sent: {}", e);
                ("failed", core::NETWORK_TEXT.to_owned())
            }
        };
        set(state, &text);
    });
}

fn send(name: &str, phone: &str, note: &str) -> hbb_common::ResultType<(u16, String)> {
    let url = format!("{}/rd/api/dolphin/callback", crate::dolphin::PORTAL_URL);
    let body = json!({
        "id": crate::ui_interface::get_id(),
        "uuid": crate::encode64(hbb_common::get_uuid()),
        "name": name,
        "phone": phone,
        "note": note,
    });
    let client = crate::hbbs_http::create_http_client_with_url_strict(&url)?;
    let response = client
        .post(&url)
        .header("Content-Type", "application/json")
        .body(body.to_string())
        .timeout(TIMEOUT)
        .send()?;
    let status = response.status().as_u16();
    Ok((status, response.text()?))
}
