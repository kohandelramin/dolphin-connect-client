//! Dolphin Connect (D5, WF-11): whether the portal can be reached right now, as the heartbeat saw it. Standard
//! library only, so CI tests it alone (`rustc --edition 2021 --test src/dolphin_portal.rs`).

#[cfg(test)]
mod tests {
    use super::*;

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
