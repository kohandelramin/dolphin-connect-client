//! Dolphin Connect, Plan 18 Phase 5 (DD-24): the apps check the settings the portal signs. The portal
//! (`app/src/lib/engine/signing.ts`) signs, with Ed25519, one canonical text per heartbeat answer:
//!
//! ```text
//! dolphin-strategy-v1\n<the PC's ID>\n<modified_at>\n<key>=<JSON string of the value>\n ... (keys sorted, the signature option left out)
//! ```
//!
//! This file rebuilds that text byte for byte and decides what to do with a strategy; `src/dolphin_strategy.rs` makes
//! the one Ed25519 call. Standard library only, so CI tests it alone
//! (`rustc --edition 2021 --test src/dolphin_strategy_core.rs`).

/// The option that carries the signature (not itself signed).
pub const SIGNATURE_OPTION: &str = "dolphin-signature";
const VERSION_LINE: &str = "dolphin-strategy-v1";

/// `JSON.stringify` of a string, as V8 writes it: `"` and `\` escaped, the five short escapes, other control characters
/// as `\u00xx` in lower case; everything else (non-ASCII, U+2028, DEL) raw. A Rust `str` cannot hold a lone surrogate,
/// which is the one other case `JSON.stringify` escapes.
pub fn json_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// The text the portal signs (`canonicalStrategy`). Keys are sorted the way JavaScript's default `sort()` does, by
/// UTF-16 code units, not by UTF-8 bytes (they differ only above U+FFFF, but the signature is exact).
pub fn canonical<'a, I>(rustdesk_id: &str, version: i64, options: I) -> String
where
    I: IntoIterator<Item = (&'a str, &'a str)>,
{
    let mut pairs: Vec<(&str, &str)> = options.into_iter().filter(|(k, _)| *k != SIGNATURE_OPTION).collect();
    pairs.sort_by(|a, b| a.0.encode_utf16().cmp(b.0.encode_utf16()));
    let mut out = format!("{VERSION_LINE}\n{rustdesk_id}\n{version}\n");
    for (k, v) in pairs {
        out.push_str(k);
        out.push('=');
        out.push_str(&json_string(v));
        out.push('\n');
    }
    out
}

/// Standard base64 with padding (what Node's `toString("base64")` writes). `None` for anything else.
pub fn base64_decode(s: &str) -> Option<Vec<u8>> {
    let b = s.as_bytes();
    if b.is_empty() || b.len() % 4 != 0 {
        return None;
    }
    let pad = b.iter().rev().take_while(|&&c| c == b'=').count();
    if pad > 2 {
        return None;
    }
    let val = |c: u8| -> Option<u32> {
        Some(match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => return None,
        } as u32)
    };
    let mut out = Vec::with_capacity(b.len() / 4 * 3);
    for (i, chunk) in b.chunks(4).enumerate() {
        let last = i == b.len() / 4 - 1;
        let n = if last { 4 - pad } else { 4 };
        let mut acc = 0u32;
        for (j, &c) in chunk.iter().enumerate() {
            let v = if j < n { val(c)? } else { 0 };
            acc |= v << (18 - 6 * j);
        }
        out.push((acc >> 16) as u8);
        if n > 2 {
            out.push((acc >> 8) as u8);
        }
        if n > 3 {
            out.push(acc as u8);
        }
        // Bits past the last byte must be zero, as in a canonical encoding.
        if (n == 2 && acc & 0xffff != 0) || (n == 3 && acc & 0xff != 0) {
            return None;
        }
    }
    Some(out)
}

/// What to do with a strategy before any key is used.
#[derive(Debug, PartialEq, Eq)]
pub enum Check {
    /// No public key compiled in (dev builds): apply it as upstream does.
    Unchecked,
    /// Refuse it (keep the previous options) without trying the key: no version, no signature, or one that is not
    /// 64 bytes of base64. The `&str` says why, for the log (never the values).
    Refuse(&'static str),
    /// Verify `signature` over `message` with `public_key`; apply only if it holds.
    Verify { public_key: [u8; 32], signature: [u8; 64], message: String },
}

/// The decision up to the Ed25519 call. `public_key_b64` is the profile's `strategy-public-key` (gen_profile.py
/// already refused a malformed one; here it is refused again rather than trusted).
pub fn check<'a, I>(public_key_b64: &str, rustdesk_id: &str, version: Option<i64>, options: I) -> Check
where
    I: IntoIterator<Item = (&'a str, &'a str)> + Clone,
{
    if public_key_b64.is_empty() {
        return Check::Unchecked;
    }
    let Some(public_key) = base64_decode(public_key_b64).and_then(|k| <[u8; 32]>::try_from(k).ok()) else {
        return Check::Refuse("the compiled-in public key is malformed");
    };
    let Some(version) = version else {
        return Check::Refuse("no modified_at beside the strategy");
    };
    let Some((_, sig)) = options.clone().into_iter().find(|(k, _)| *k == SIGNATURE_OPTION) else {
        return Check::Refuse("unsigned");
    };
    let Some(signature) = base64_decode(sig).and_then(|s| <[u8; 64]>::try_from(s).ok()) else {
        return Check::Refuse("malformed signature");
    };
    Check::Verify { public_key, signature, message: canonical(rustdesk_id, version, options) }
}

/// The heartbeat's `dolphin_sig` field: `"bad"` while the last strategy was refused, so the portal audits
/// `engine.strategy_rejected`; nothing otherwise (the portal ignores a missing field).
pub fn heartbeat_sig(last_refused: bool) -> Option<&'static str> {
    if last_refused {
        Some("bad")
    } else {
        None
    }
}

/// After a heartbeat answer: whether the refusal flag is set. A refused strategy sets it, an applied one (checked or
/// unchecked) clears it, and an answer without a strategy leaves it as it was.
pub fn refused_after(previous: bool, strategy: Option<bool>) -> bool {
    match strategy {
        Some(applied) => !applied,
        None => previous,
    }
}

/// Whether to store the answer's `modified_at` as the strategy version the next heartbeat reports. A refused strategy
/// keeps the old one, so the portal sends its settings again on the next heartbeat (it sends them only when the
/// versions differ) instead of believing the PC has them.
pub fn store_version(strategy_applied: Option<bool>) -> bool {
    strategy_applied.unwrap_or(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    // dolphin/strategy-signature-vector.json, made by the portal's signing.ts with a throwaway key. Its `canonical`
    // must come out byte for byte; dolphin/test_workflows.py checks these strings match the file.
    const VECTOR_ID: &str = "123456789";
    const VECTOR_VERSION: i64 = 1794582781;
    const VECTOR_PUBLIC_KEY: &str = "ZuS26V7Tw2nnrbswkPHSPvunNt3d1x6Gi+LXDqo3PLc=";
    const VECTOR_SIGNATURE: &str =
        "wRq8eXp0zWPoqa0nkqIQZDMrjHgYGMu08iZQ4VWMwWVvEHgF25YCt7/Fh88uHCKq7AfTlXN8R6HaWf+tfxZTAg==";
    const VECTOR_CANONICAL: &str = "dolphin-strategy-v1\n123456789\n1794582781\napprove-mode=\"password\"\ndolphin-support-phone=\"021-44280505\"\ndolphin-tech-name=\"علی رضایی\"\nenable-block-input=\"N\"\n";

    fn vector_options() -> Vec<(&'static str, &'static str)> {
        // Deliberately out of order, with the signature among them, as a HashMap would hand them over.
        vec![
            ("enable-block-input", "N"),
            (SIGNATURE_OPTION, VECTOR_SIGNATURE),
            ("dolphin-tech-name", "علی رضایی"),
            ("approve-mode", "password"),
            ("dolphin-support-phone", "021-44280505"),
        ]
    }

    #[test]
    fn the_portal_vector_comes_out_byte_for_byte() {
        let text = canonical(VECTOR_ID, VECTOR_VERSION, vector_options());
        assert_eq!(text, VECTOR_CANONICAL);
        assert_eq!(text.as_bytes(), VECTOR_CANONICAL.as_bytes());
    }

    #[test]
    fn the_vector_is_handed_to_the_key_with_its_canonical_text() {
        match check(VECTOR_PUBLIC_KEY, VECTOR_ID, Some(VECTOR_VERSION), vector_options()) {
            Check::Verify { public_key, signature, message } => {
                assert_eq!(public_key.to_vec(), base64_decode(VECTOR_PUBLIC_KEY).unwrap());
                assert_eq!(signature.to_vec(), base64_decode(VECTOR_SIGNATURE).unwrap());
                assert_eq!(message, VECTOR_CANONICAL);
            }
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn another_id_or_version_changes_the_signed_text() {
        assert_ne!(canonical("987654321", VECTOR_VERSION, vector_options()), VECTOR_CANONICAL);
        assert_ne!(canonical(VECTOR_ID, VECTOR_VERSION + 1, vector_options()), VECTOR_CANONICAL);
        let mut changed = vector_options();
        changed[0].1 = "Y";
        assert_ne!(canonical(VECTOR_ID, VECTOR_VERSION, changed), VECTOR_CANONICAL);
    }

    #[test]
    fn json_strings_are_escaped_like_json_stringify() {
        assert_eq!(json_string(""), "\"\"");
        assert_eq!(json_string("a\"b\\c"), "\"a\\\"b\\\\c\"");
        assert_eq!(json_string("\u{8}\u{c}\n\r\t"), "\"\\b\\f\\n\\r\\t\"");
        assert_eq!(json_string("\u{0}\u{1}\u{1f}\u{b}"), "\"\\u0000\\u0001\\u001f\\u000b\"");
        // Not escaped by JSON.stringify: '/', DEL, U+2028, non-ASCII, emoji.
        assert_eq!(json_string("/\u{7f}\u{2028}علی😀"), "\"/\u{7f}\u{2028}علی😀\"");
        // A real option value: the recent-sessions JSON is itself a string, so its quotes are escaped once.
        assert_eq!(json_string("[{\"a\":1}]"), "\"[{\\\"a\\\":1}]\"");
    }

    #[test]
    fn keys_sort_by_utf16_like_javascript() {
        // U+FF61 sorts after U+1F600 in UTF-8 bytes order but before it in UTF-16 (0xFF61 < 0xD83D).
        let text = canonical("1", 1, vec![("😀", "a"), ("｡", "b"), ("Z", "c"), ("a", "d")]);
        assert_eq!(text, "dolphin-strategy-v1\n1\n1\nZ=\"c\"\na=\"d\"\n😀=\"a\"\n｡=\"b\"\n");
    }

    #[test]
    fn an_empty_strategy_and_a_negative_version() {
        assert_eq!(canonical("1", -5, Vec::new()), "dolphin-strategy-v1\n1\n-5\n");
        assert_eq!(canonical("1", 0, vec![(SIGNATURE_OPTION, "x")]), "dolphin-strategy-v1\n1\n0\n");
    }

    #[test]
    fn without_a_key_nothing_is_checked() {
        assert_eq!(check("", VECTOR_ID, None, Vec::new()), Check::Unchecked);
        assert_eq!(check("", VECTOR_ID, Some(1), vector_options()), Check::Unchecked);
    }

    #[test]
    fn with_a_key_unsigned_or_malformed_strategies_are_refused() {
        let unsigned: Vec<_> = vector_options().into_iter().filter(|(k, _)| *k != SIGNATURE_OPTION).collect();
        assert_eq!(check(VECTOR_PUBLIC_KEY, VECTOR_ID, Some(1), unsigned), Check::Refuse("unsigned"));
        assert_eq!(check(VECTOR_PUBLIC_KEY, VECTOR_ID, None, vector_options()), Check::Refuse("no modified_at beside the strategy"));
        for bad in ["", "-", "abc", "wRq8eXp0zWPoqa0nkqIQZDMrjHgYGMu08iZQ4VWMwWU=", &format!("{VECTOR_SIGNATURE}AAAA")] {
            let opts = vec![(SIGNATURE_OPTION, bad), ("approve-mode", "password")];
            assert_eq!(check(VECTOR_PUBLIC_KEY, VECTOR_ID, Some(1), opts), Check::Refuse("malformed signature"), "{bad}");
        }
        assert_eq!(
            check("AAAA", VECTOR_ID, Some(1), vector_options()),
            Check::Refuse("the compiled-in public key is malformed")
        );
    }

    #[test]
    fn base64_is_strict() {
        assert_eq!(base64_decode("TWFu").unwrap(), b"Man");
        assert_eq!(base64_decode("TWE=").unwrap(), b"Ma");
        assert_eq!(base64_decode("TQ==").unwrap(), b"M");
        assert_eq!(base64_decode(VECTOR_PUBLIC_KEY).unwrap().len(), 32);
        assert_eq!(base64_decode(VECTOR_SIGNATURE).unwrap().len(), 64);
        for bad in ["", "TWF", "TW=u", "T===", "TWE", "TR==", "TWF=", "TW\u{e9}u", "TW-u", "TW_u", " TWu"] {
            assert_eq!(base64_decode(bad), None, "{bad:?}");
        }
    }

    #[test]
    fn the_heartbeat_says_bad_until_a_strategy_is_applied() {
        assert_eq!(heartbeat_sig(false), None);
        assert_eq!(heartbeat_sig(true), Some("bad"));
        assert!(refused_after(false, Some(false)));
        assert!(refused_after(true, None));
        assert!(!refused_after(false, None));
        assert!(!refused_after(true, Some(true)));
    }

    #[test]
    fn a_refused_strategy_keeps_the_old_version_so_the_portal_sends_again() {
        assert!(store_version(None));
        assert!(store_version(Some(true)));
        assert!(!store_version(Some(false)));
    }
}
