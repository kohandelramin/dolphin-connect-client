//! Dolphin Connect (D5, WF-11): whether the portal can be reached right now, as the heartbeat saw it. Standard
//! library only, so CI tests it alone (`rustc --edition 2021 --test src/dolphin_portal.rs`).

/// The local option the customer app's accept prompt reads (it runs in another process, `--cm`, and reads options
/// over IPC like `dolphin-tech-id`). "Y" while the heartbeat is failing; empty otherwise.
pub const PORTAL_DOWN_OPTION: &str = "dolphin-portal-down";

/// What to write after a heartbeat, given the option's current value: `Some(v)` only when the state changes (no config
/// write every 3 s). One failure sets "Y"; one success clears it.
pub fn portal_down_write(current: &str, reachable: bool) -> Option<&'static str> {
    match (current == "Y", reachable) {
        (false, false) => Some("Y"),
        (true, true) => Some(""),
        _ => None,
    }
}

/// Did the portal itself answer the heartbeat? `post_request` returns `Ok` for every HTTP status, so a 502/503 page from
/// the reverse proxy in front of a stopped or redeploying portal looks like an answer. The portal's heartbeat route
/// always answers a JSON object (app/src/app/rd/api/heartbeat/route.ts), so only a body that starts with `{` counts.
pub fn portal_answered(body: &str) -> bool {
    body.trim_start().starts_with('{')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_portal_answered_only_with_its_json() {
        assert!(portal_answered("{}"));
        assert!(portal_answered(r#"{"sysinfo":true,"strategy":{}}"#));
        assert!(portal_answered("  \n{\"a\":1}")); // whitespace before the JSON
        assert!(!portal_answered("<html><body>502 Bad Gateway</body></html>")); // the reverse proxy's error page
        assert!(!portal_answered("Bad Gateway"));
        assert!(!portal_answered(""));
        assert!(!portal_answered("   \n"));
    }

    #[test]
    fn the_option_is_written_only_when_the_state_changes() {
        assert_eq!(portal_down_write("", false), Some("Y")); // the first failure is enough
        assert_eq!(portal_down_write("Y", false), None); // still down: no config write every 3 s
        assert_eq!(portal_down_write("Y", true), Some("")); // one success clears it
        assert_eq!(portal_down_write("", true), None);
        assert_eq!(portal_down_write("N", true), None); // anything but "Y" counts as clear
        assert_eq!(portal_down_write("N", false), Some("Y"));
        assert_eq!(PORTAL_DOWN_OPTION, "dolphin-portal-down");
    }
}
