//! Dolphin Connect (TB-20): an update started by the old app. The packer tells the app where it is, and an updated
//! packer waits for the old app to exit before it unpacks over it. Std only apart from the Windows wait, so CI
//! tests it alone: rustc --edition 2021 --test libs/portable/src/dolphin_wait.rs

/// Set by the old app on the new packer it starts (src/dolphin_update.rs).
pub const WAIT_PID_ENV: &str = "DOLPHIN_WAIT_PID";
/// Set by the packer on the app: the full path of the exe the customer started.
pub const PACKER_ENV: &str = "DOLPHIN_PACKER";
pub const WAIT_MS: u32 = 30_000;

/// The pid to wait for: digits only, not zero, not ourselves.
pub fn parse_pid(value: Option<&str>, own_pid: u32) -> Option<u32> {
    let v = value?;
    if v.is_empty() || !v.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let pid: u32 = v.parse().ok()?;
    if pid == 0 || pid == own_pid {
        None
    } else {
        Some(pid)
    }
}

/// Waits until the process has exited (true) or the time is up (false). A pid that is already gone returns at once.
#[cfg(windows)]
pub fn wait_for_exit(pid: u32, timeout_ms: u32) -> bool {
    use winapi::um::{handleapi::CloseHandle, processthreadsapi::OpenProcess, synchapi::WaitForSingleObject, winbase::WAIT_OBJECT_0, winnt::SYNCHRONIZE};
    unsafe {
        let handle = OpenProcess(SYNCHRONIZE, 0, pid);
        if handle.is_null() {
            return true;
        }
        let done = WaitForSingleObject(handle, timeout_ms) == WAIT_OBJECT_0;
        CloseHandle(handle);
        done
    }
}

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
