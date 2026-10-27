//! Dolphin Connect (TB-20): the pure part of the update before the app opens. Standard library only, so CI tests
//! it alone (`rustc --edition 2021 --test src/dolphin_update_core.rs`); the full crate needs vcpkg and Windows.
//! src/dolphin_update.rs does the network and file work around these rules. The Persian texts live here so the
//! Flutter (x64) and Sciter (x86) screens say the same words.

use std::cmp::Ordering;
use std::path::{Path, PathBuf};

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
