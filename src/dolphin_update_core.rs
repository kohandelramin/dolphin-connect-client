//! Dolphin Connect (TB-20): the pure part of the update before the app opens. Standard library only, so CI tests
//! it alone (`rustc --edition 2021 --test src/dolphin_update_core.rs`); the full crate needs vcpkg and Windows.
//! src/dolphin_update.rs does the network and file work around these rules. The Persian texts live here so the
//! Flutter (x64) and Sciter (x86) screens say the same words.

use std::cmp::Ordering;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

/// A Dolphin version: X.Y.Z, X.Y.Z-rc.N (release candidate) or X.Y.Z-dev.N (test build), in SemVer order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Version {
    core: (u64, u64, u64),
    pre: Option<(String, u64)>,
}

impl Ord for Version {
    fn cmp(&self, other: &Self) -> Ordering {
        self.core.cmp(&other.core).then_with(|| match (&self.pre, &other.pre) {
            (None, None) => Ordering::Equal,
            (None, Some(_)) => Ordering::Greater, // 2.0.0 is newer than 2.0.0-rc.1
            (Some(_), None) => Ordering::Less,
            (Some(a), Some(b)) => a.cmp(b), // "dev" < "rc", then the number
        })
    }
}

impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

fn number(s: &str) -> Option<u64> {
    if s.is_empty() || s.len() > 9 || !s.bytes().all(|b| b.is_ascii_digit()) || (s.len() > 1 && s.starts_with('0')) {
        return None;
    }
    s.parse().ok()
}

pub fn parse_version(s: &str) -> Option<Version> {
    let (core, pre) = match s.split_once('-') {
        Some((c, p)) => (c, Some(p)),
        None => (s, None),
    };
    let mut parts = core.split('.');
    let major = number(parts.next()?)?;
    let minor = number(parts.next()?)?;
    let patch = number(parts.next()?)?;
    if parts.next().is_some() {
        return None;
    }
    let pre = match pre {
        None => None,
        Some(p) => {
            let (kind, n) = p.split_once('.')?;
            if kind != "dev" && kind != "rc" {
                return None;
            }
            Some((kind.to_owned(), number(n)?))
        }
    };
    Some(Version { core: (major, minor, patch), pre })
}

/// True only when both are Dolphin versions and `latest` is newer: a version we cannot compare never updates.
pub fn is_newer(current: &str, latest: &str) -> bool {
    match (parse_version(current), parse_version(latest)) {
        (Some(c), Some(l)) => l > c,
        _ => false,
    }
}

/// Releases and release candidates update themselves, test builds (-dev.N) never (so a test build can be tried
/// against the live portal), and only from an https portal (the dev profile's http://127.0.0.1 never).
pub fn updates_enabled(current: &str, portal_url: &str) -> bool {
    portal_url.starts_with("https://")
        && parse_version(current).map_or(false, |v| v.pre.as_ref().map_or(true, |(kind, _)| kind == "rc"))
}

/// The portal's build names (app/src/lib/client.ts BUILDS).
pub fn build_name(outgoing_only: bool, x86: bool) -> &'static str {
    if outgoing_only {
        "technician-x64"
    } else if x86 {
        "customer-x86"
    } else {
        "customer-x64"
    }
}

/// Larger than any build we ship (about 25 MB today); the portal's manifest allows the same.
pub const MAX_SIZE: u64 = 200 * 1024 * 1024;

/// What the portal offers (GET /api/client/latest). `path` is None for the staff-only technician file (D13).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Offer {
    pub version: String,
    pub sha256: String,
    pub size: u64,
    pub path: Option<String>,
}

/// Accepts the portal's answer only if it is for this build, well formed, and its file is on the portal's own
/// /download route (the app adds the compiled-in portal address, so the file can never come from elsewhere).
pub fn check_offer(build: &str, answer_build: &str, version: &str, sha256: &str, size: u64, path: Option<&str>) -> Result<Offer, &'static str> {
    if answer_build != build {
        return Err("another build");
    }
    if parse_version(version).is_none() {
        return Err("version");
    }
    if sha256.len() != 64 || !sha256.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f')) {
        return Err("sha256");
    }
    if size == 0 || size > MAX_SIZE {
        return Err("size");
    }
    if let Some(p) = path {
        if !valid_download_path(p) {
            return Err("path");
        }
    }
    Ok(Offer { version: version.to_owned(), sha256: sha256.to_owned(), size, path: path.map(str::to_owned) })
}

pub fn valid_download_path(p: &str) -> bool {
    let Some(name) = p.strip_prefix("/download/") else {
        return false;
    };
    name.len() > 4
        && name.len() <= 100
        && name.ends_with(".exe")
        && !name.contains("..")
        && name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-')
}

/// The download is used only when both its size and its SHA-256 match the portal's answer.
pub fn verify(offer: &Offer, received: u64, sha256_hex: &str) -> Result<(), &'static str> {
    if received != offer.size {
        return Err("size");
    }
    if sha256_hex != offer.sha256 {
        return Err("hash");
    }
    Ok(())
}

/// `…\DolphinConnect-2.0.0.exe` + ".old" → `…\DolphinConnect-2.0.0.exe.old`, in the same folder.
pub fn sibling(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.file_name().map(|n| n.to_os_string()).unwrap_or_default();
    name.push(suffix);
    path.with_file_name(name)
}

/// A swap to the same version that started less than this long ago and left us running is not retried by itself.
pub const RETRY_AFTER_SECS: u64 = 600;

pub fn attempt_value(version: &str, now: u64) -> String {
    format!("{version} {now}")
}

/// False when the last swap to `latest` started less than 10 minutes ago and we are still the old app: that swap
/// failed, and trying again at once could loop. The screen then says so; «تلاش دوباره» still tries.
pub fn may_attempt(stored: &str, latest: &str, now: u64) -> bool {
    let mut it = stored.split(' ');
    match (it.next(), it.next().and_then(|t| t.parse::<u64>().ok())) {
        (Some(v), Some(at)) if v == latest => now.saturating_sub(at) >= RETRY_AFTER_SECS,
        _ => true,
    }
}

/// No new bytes for this long, once the answer has started: the download is given up on (review I1). Whole-request
/// cap stays in dolphin_update.rs.
pub const STALL_LIMIT: Duration = Duration::from_secs(30);
/// Before the answer starts the strict client may probe the portal first (about 30 s each), so waiting for the first
/// byte is allowed longer than a stall in the middle of the file.
pub const FIRST_BYTE_LIMIT: Duration = Duration::from_secs(60);

/// True when nothing arrived since `last_progress` for `limit`. A clock that went backwards is never a stall.
pub fn stalled(last_progress: Instant, now: Instant, limit: Duration) -> bool {
    now.saturating_duration_since(last_progress) >= limit
}

/// The update never swaps the app while someone is connected (review I3): a swap kills the service and the window.
pub fn may_apply(connected: usize) -> bool {
    connected == 0
}

/// D19: the install goes on only if the customer did not choose «ادامه با همین نسخه» while it waited, and nobody is
/// connected. Continuing never cuts a session and never swaps the app afterwards.
pub fn install_may_go_on(continued: bool, connected: usize) -> bool {
    !continued && may_apply(connected)
}

/// «ادامه با همین نسخه» is offered while a session holds the install back, so a lost IPC link never strands the customer.
pub fn continue_offered_while_waiting(waiting: bool) -> bool {
    waiting
}

/// Installed app: after the elevated update is started, upstream's `update_me` ends this process and restarts the
/// main window. If that never happens we leave after this long, so the screen never hangs (review I2).
pub const INSTALLED_EXIT_FALLBACK: Duration = Duration::from_secs(120);

/// One text for `ready` and `applying` in both screens, and one while a session keeps the install waiting.
pub const APPLYING_TEXT: &str = "در حال نصب…";
pub const WAITING_TEXT: &str = "پس از پایان جلسه نصب می‌شود.";

pub fn install_text(waiting: bool) -> &'static str {
    if waiting {
        WAITING_TEXT
    } else {
        APPLYING_TEXT
    }
}

/// «دریافت دستی»: the panel's «حساب من» page for the staff-only technician file (D13), else the public page.
pub fn download_page(portal: &str, staff: bool) -> String {
    format!("{portal}{}", if staff { "/staff/me" } else { "/download" })
}

pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Latin digits to Persian, for display only.
pub fn fa_digits(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '0'..='9' => char::from_u32(0x06F0 + (c as u32 - '0' as u32)).unwrap_or(c),
            _ => c,
        })
        .collect()
}

/// Megabytes with one decimal, Persian digits and the Persian decimal separator: 25_829_888 → «۲۴٫۶».
pub fn megabytes(bytes: u64) -> String {
    let tenths = (bytes * 10 + 524_288) / 1_048_576;
    fa_digits(&format!("{}.{}", tenths / 10, tenths % 10)).replace('.', "٫")
}

pub fn percent(received: u64, total: u64) -> u64 {
    if total == 0 {
        0
    } else {
        received.min(total) * 100 / total
    }
}

pub fn progress_text(received: u64, total: u64) -> String {
    format!("{} از {} مگابایت", megabytes(received), megabytes(total))
}

pub fn lead_text(version: &str) -> String {
    format!(
        "نسخه‌ی {} آماده است. پیش از باز شدن برنامه، نسخه‌ی تازه دریافت و جایگزین می‌شود.",
        fa_digits(version)
    )
}

/// The technician app (its file is for signed-in staff only, D13).
pub fn manual_text(version: &str) -> String {
    format!(
        "نسخه‌ی {} برنامه‌ی کارشناس آماده است. آن را از پنل دلفین دریافت کنید و به جای این برنامه اجرا کنید.",
        fa_digits(version)
    )
}

pub fn error_text(reason: &str) -> &'static str {
    match reason {
        "network" => "دریافت نسخه‌ی تازه کامل نشد. اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.",
        "size" | "hash" => "فایل دریافت‌شده با نسخه‌ی دلفین یکی نبود و کنار گذاشته شد. برنامه‌ی شما تغییری نکرد.",
        "write" => "نسخه‌ی تازه را نتوانستیم کنار برنامه ذخیره کنیم. برنامه‌ی شما تغییری نکرد.",
        "elevation" => "برای نصب نسخه‌ی تازه اجازه‌ی مدیر ویندوز لازم است. دوباره تلاش کنید و در پنجره‌ی ویندوز «بله» را بزنید.",
        // The elevated installer never ended this process (unpack or AV failure, UAC closed).
        "installer" => "نصب نسخه‌ی تازه کامل نشد. برنامه‌ی شما تغییری نکرد. دوباره تلاش کنید یا با همین نسخه ادامه دهید.",
        "blocked" => "به‌روزرسانی خودکار چند دقیقه پیش انجام نشد.",
        _ => "به‌روزرسانی خودکار انجام نشد.",
    }
}

pub fn phone_text(phone: &str) -> String {
    if phone.trim().is_empty() {
        "اگر درست نشد با پشتیبانی دلفین تماس بگیرید.".to_owned()
    } else {
        format!("اگر درست نشد با پشتیبانی دلفین تماس بگیرید: {}", fa_digits(phone.trim()))
    }
}

/// The numbers the portal pushed (`dolphin-support-phone`; "-" means empty), else the compiled one.
pub fn pick_phone(pushed: &str, compiled: &str) -> String {
    let p = pushed.trim();
    if p.is_empty() || p == "-" {
        compiled.to_owned()
    } else {
        p.to_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SHA: &str = "a386381bde59a6cc9d804469fb27b1df16bb0c3085ffc2cb1a28c46b388654f3";

    #[test]
    fn versions_order_like_semver_and_like_the_portal() {
        let sorted = ["2.0.0-dev.9", "2.0.0-dev.10", "2.0.0-rc.1", "2.0.0-rc.2", "2.0.0", "2.0.1", "2.1.0", "10.0.0"];
        for pair in sorted.windows(2) {
            assert!(is_newer(pair[0], pair[1]), "{} < {}", pair[0], pair[1]);
            assert!(!is_newer(pair[1], pair[0]), "{} > {}", pair[1], pair[0]);
        }
        assert!(!is_newer("2.0.0", "2.0.0"));
    }

    #[test]
    fn only_dolphin_versions_compare() {
        for bad in ["1.5.0-dc.4", "v2.0.0", "2.0", "02.0.0", "2.0.0-beta.1", "2.0.0-rc.01", "2.0.0 ", "", "2.0.0-rc", "2.0.0.1"] {
            assert!(parse_version(bad).is_none(), "{bad:?}");
            assert!(!is_newer("2.0.0", bad) && !is_newer(bad, "2.0.0"), "{bad:?}");
        }
    }

    #[test]
    fn test_builds_and_plain_http_never_update() {
        assert!(updates_enabled("2.0.0", "https://support.dolphindev.ir"));
        assert!(updates_enabled("2.0.0-rc.1", "https://support.dolphindev.ir"));
        assert!(!updates_enabled("2.0.0-dev.412", "https://support.dolphindev.ir"));
        assert!(!updates_enabled("2.0.0", "http://127.0.0.1:3010"));
        assert!(!updates_enabled("nonsense", "https://support.dolphindev.ir"));
    }

    #[test]
    fn build_names_match_the_portal() {
        assert_eq!(build_name(false, false), "customer-x64");
        assert_eq!(build_name(false, true), "customer-x86");
        assert_eq!(build_name(true, false), "technician-x64");
    }

    #[test]
    fn a_good_answer_becomes_an_offer() {
        let offer = check_offer("customer-x64", "customer-x64", "2.0.1", SHA, 25_829_888, Some("/download/DolphinConnect-2.0.1.exe")).unwrap();
        assert_eq!(offer, Offer { version: "2.0.1".into(), sha256: SHA.into(), size: 25_829_888, path: Some("/download/DolphinConnect-2.0.1.exe".into()) });
        assert_eq!(check_offer("technician-x64", "technician-x64", "2.0.1", SHA, 1, None).unwrap().path, None);
    }

    #[test]
    fn answers_that_point_elsewhere_or_look_wrong_are_refused() {
        let ok = "/download/DolphinConnect-2.0.1.exe";
        assert_eq!(check_offer("customer-x64", "customer-x86", "2.0.1", SHA, 1, Some(ok)), Err("another build"));
        assert_eq!(check_offer("customer-x64", "customer-x64", "2.0.1-beta", SHA, 1, Some(ok)), Err("version"));
        assert_eq!(check_offer("customer-x64", "customer-x64", "2.0.1", &SHA.to_uppercase(), 1, Some(ok)), Err("sha256"));
        assert_eq!(check_offer("customer-x64", "customer-x64", "2.0.1", &SHA[..63], 1, Some(ok)), Err("sha256"));
        assert_eq!(check_offer("customer-x64", "customer-x64", "2.0.1", SHA, 0, Some(ok)), Err("size"));
        assert_eq!(check_offer("customer-x64", "customer-x64", "2.0.1", SHA, MAX_SIZE + 1, Some(ok)), Err("size"));
        for bad in ["https://evil.example/x.exe", "//evil.example/x.exe", "/download/../etc/x.exe", "/download/a b.exe", "/download/x.msi", "/api/x.exe", "/download/x.exe?y=1", "/download/"] {
            assert!(!valid_download_path(bad), "{bad:?}");
            assert_eq!(check_offer("customer-x64", "customer-x64", "2.0.1", SHA, 1, Some(bad)), Err("path"), "{bad:?}");
        }
    }

    #[test]
    fn a_download_is_used_only_when_size_and_hash_match() {
        let offer = Offer { version: "2.0.1".into(), sha256: SHA.into(), size: 10, path: None };
        assert_eq!(verify(&offer, 10, SHA), Ok(()));
        assert_eq!(verify(&offer, 9, SHA), Err("size"));
        assert_eq!(verify(&offer, 10, &"0".repeat(64)), Err("hash"));
    }

    #[test]
    fn siblings_keep_the_customers_file_name() {
        let p = Path::new("dir").join("DolphinConnect-2.0.0.exe");
        assert_eq!(sibling(&p, ".old"), Path::new("dir").join("DolphinConnect-2.0.0.exe.old"));
        assert_eq!(sibling(&p, ".new"), Path::new("dir").join("DolphinConnect-2.0.0.exe.new"));
    }

    #[test]
    fn a_failed_swap_is_not_retried_at_once() {
        let stored = attempt_value("2.0.1", 1_000);
        assert!(!may_attempt(&stored, "2.0.1", 1_000 + RETRY_AFTER_SECS - 1));
        assert!(may_attempt(&stored, "2.0.1", 1_000 + RETRY_AFTER_SECS));
        assert!(may_attempt(&stored, "2.0.2", 1_001));
        assert!(may_attempt("", "2.0.1", 1_001));
        assert!(may_attempt("garbage", "2.0.1", 1_001));
    }

    #[test]
    fn a_download_that_stops_is_stalled_after_the_limit() {
        use std::time::{Duration, Instant};
        let start = Instant::now();
        let limit = Duration::from_secs(30);
        assert!(!stalled(start, start, limit));
        assert!(!stalled(start, start + Duration::from_secs(29), limit));
        assert!(stalled(start, start + Duration::from_secs(30), limit));
        assert!(stalled(start, start + Duration::from_secs(300), limit));
        // A clock that went backwards is never a stall.
        assert!(!stalled(start + Duration::from_secs(5), start, limit));
        assert!(STALL_LIMIT <= Duration::from_secs(30));
        assert!(FIRST_BYTE_LIMIT >= STALL_LIMIT);
    }

    #[test]
    fn the_update_waits_while_anyone_is_connected() {
        assert!(may_apply(0));
        assert!(!may_apply(1));
        assert!(!may_apply(7));
    }

    #[test]
    fn continuing_stops_the_install_and_waiting_offers_continue() {
        assert!(install_may_go_on(false, 0));
        assert!(!install_may_go_on(false, 1));
        assert!(!install_may_go_on(true, 0)); // chose to continue: never swap afterwards
        assert!(!install_may_go_on(true, 3));
        assert!(continue_offered_while_waiting(true));
        assert!(!continue_offered_while_waiting(false));
    }

    #[test]
    fn the_installer_fallback_has_a_persian_reason() {
        let t = error_text("installer");
        assert!(t.contains("نصب") && t != error_text("unknown"));
    }

    #[test]
    fn one_text_for_installing_and_one_for_waiting() {
        assert_eq!(APPLYING_TEXT, "در حال نصب…");
        assert_eq!(WAITING_TEXT, "پس از پایان جلسه نصب می‌شود.");
        assert_eq!(install_text(false), APPLYING_TEXT);
        assert_eq!(install_text(true), WAITING_TEXT);
    }

    #[test]
    fn the_manual_action_opens_the_panel_for_staff_and_the_download_page_for_customers() {
        assert_eq!(download_page("https://support.dolphindev.ir", true), "https://support.dolphindev.ir/staff/me");
        assert_eq!(download_page("https://support.dolphindev.ir", false), "https://support.dolphindev.ir/download");
    }

    #[test]
    fn the_installed_exit_fallback_is_two_minutes() {
        assert_eq!(INSTALLED_EXIT_FALLBACK, std::time::Duration::from_secs(120));
    }

    #[test]
    fn hex_is_lowercase_and_two_digits_per_byte() {
        assert_eq!(hex(&[0x00, 0x0f, 0xa3, 0xff]), "000fa3ff");
    }

    #[test]
    fn persian_texts() {
        assert_eq!(fa_digits("2.0.1"), "۲.۰.۱");
        assert_eq!(megabytes(25_829_888), "۲۴٫۶");
        assert_eq!(megabytes(12_582_912), "۱۲٫۰");
        assert_eq!(percent(12_582_912, 25_829_888), 48);
        assert_eq!(percent(5, 0), 0);
        assert_eq!(percent(30, 20), 100);
        assert_eq!(progress_text(12_582_912, 25_829_888), "۱۲٫۰ از ۲۴٫۶ مگابایت");
        assert!(lead_text("2.0.1").starts_with("نسخه‌ی ۲.۰.۱ آماده است."));
        assert!(manual_text("2.0.1").contains("پنل"));
        assert_eq!(error_text("hash"), error_text("size"));
        assert!(error_text("hash").contains("تغییری نکرد"));
        assert!(!error_text("something new").is_empty());
        assert_eq!(phone_text("021-44200250"), "اگر درست نشد با پشتیبانی دلفین تماس بگیرید: ۰۲۱-۴۴۲۰۰۲۵۰");
        assert_eq!(phone_text(""), "اگر درست نشد با پشتیبانی دلفین تماس بگیرید.");
        assert_eq!(pick_phone(" 021-1 ", "021-2"), "021-1");
        assert_eq!(pick_phone("-", "021-2"), "021-2");
        assert_eq!(pick_phone("", "021-2"), "021-2");
    }
}
