//! Dolphin Connect (TB-20): an update started by the old app. The packer tells the app where it is, and an updated
//! packer waits for the old app to exit before it unpacks over it. Std only apart from the Windows wait, so CI
//! tests it alone: rustc --edition 2021 --test libs/portable/src/dolphin_wait.rs

/// Set by the old app on the new packer it starts (src/dolphin_update.rs).
pub const WAIT_PID_ENV: &str = "DOLPHIN_WAIT_PID";
/// Set by the packer on the app: the full path of the exe the customer started.
pub const PACKER_ENV: &str = "DOLPHIN_PACKER";
pub const WAIT_MS: u32 = 30_000;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_pid_accepts_only_another_process() {
        assert_eq!(parse_pid(Some("4242"), 1), Some(4242));
        for bad in [Some("1"), Some("0"), Some("-5"), Some("abc"), Some(""), Some(" 42"), Some("99999999999"), None] {
            assert_eq!(parse_pid(bad, 1), None, "{bad:?}");
        }
    }
}
