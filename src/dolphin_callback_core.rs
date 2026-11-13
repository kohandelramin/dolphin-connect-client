//! Dolphin Connect (Plan 14, B6): the rules of «با من تماس بگیرید», std only so CI tests it with plain rustc.
//! The sending lives in src/dolphin_callback.rs; the portal side is app/src/lib/app-callback.ts in the portal repo.

/// Shown when the portal could not be reached at all.
pub const NETWORK_TEXT: &str = "به پورتال دلفین وصل نشد؛ با پشتیبانی دلفین تماس بگیرید.";

/// Persian and Arabic-Indic digits to Latin, so «۰۹۱۲» and "0912" are the same number.
pub fn latin_digits(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '۰'..='۹' => char::from_digit(c as u32 - '۰' as u32, 10).unwrap_or(c),
            '٠'..='٩' => char::from_digit(c as u32 - '٠' as u32, 10).unwrap_or(c),
            _ => c,
        })
        .collect()
}

/// The phone as the portal wants it: digits only (a leading + stays), 7 to 15 of them. None otherwise.
pub fn normalize_phone(raw: &str) -> Option<String> {
    let s: String = latin_digits(raw).chars().filter(|c| !matches!(c, ' ' | '-' | '(' | ')' | '.')).collect();
    let digits = s.strip_prefix('+').unwrap_or(&s);
    if (7..=15).contains(&digits.len()) && digits.chars().all(|c| c.is_ascii_digit()) {
        Some(s)
    } else {
        None
    }
}

/// Checks the form before anything is sent. Ok: (name, phone, note), cleaned. Err: what to tell the customer.
pub fn check(name: &str, phone: &str, note: &str) -> Result<(String, String, String), &'static str> {
    let name = name.split_whitespace().collect::<Vec<_>>().join(" ");
    if name.is_empty() || name.chars().count() > 60 {
        return Err("نام خود را بنویسید (حداکثر ۶۰ نویسه).");
    }
    let Some(phone) = normalize_phone(phone) else {
        return Err("شماره‌ی تلفن را درست بنویسید؛ مثلاً ۰۹۱۲۳۴۵۶۷۸۹.");
    };
    let note: String = note.trim().chars().take(500).collect();
    Ok((name, phone, note))
}

fn number_in(body: &str) -> Option<u64> {
    let at = body.find("\"number\":")? + "\"number\":".len();
    let digits: String = body[at..].trim_start().chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse().ok()
}

fn persian(n: u64) -> String {
    latin_to_persian(&n.to_string())
}

fn latin_to_persian(s: &str) -> String {
    s.chars().map(|c| c.to_digit(10).map(|d| char::from_u32('۰' as u32 + d).unwrap_or(c)).unwrap_or(c)).collect()
}

/// What the portal's answer means for the customer: (asked successfully, the text to show).
pub fn answer_text(status: u16, body: &str) -> (bool, String) {
    if status == 429 {
        return (false, "چند بار پشت سر هم فرستاده شد؛ چند دقیقه بعد دوباره امتحان کنید.".to_owned());
    }
    if status != 200 {
        return (false, NETWORK_TEXT.to_owned());
    }
    let number = number_in(body).map(persian).unwrap_or_default();
    if body.contains("\"ok\":true") {
        return (true, format!("درخواست شما ثبت شد (شماره‌ی {number}). کارشناس دلفین با شما تماس می‌گیرد."));
    }
    if body.contains("\"reason\":\"already\"") {
        return (true, format!("درخواست قبلی شما (شماره‌ی {number}) در صف است؛ کارشناس دلفین با شما تماس می‌گیرد."));
    }
    if body.contains("\"reason\":\"not_linked\"") {
        return (false, "این رایانه هنوز به دلفین معرفی نشده است؛ با پشتیبانی دلفین تماس بگیرید.".to_owned());
    }
    if body.contains("\"reason\":\"invalid\"") {
        return (false, "نام یا شماره‌ی تلفن پذیرفته نشد؛ دوباره بنویسید.".to_owned());
    }
    (false, "دلفین هنوز این رایانه را نمی‌شناسد؛ چند لحظه بعد دوباره امتحان کنید یا تماس بگیرید.".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn phones_in_persian_or_latin_digits_with_spaces_are_the_same() {
        assert_eq!(normalize_phone("۰۹۱۲ ۳۴۵ ۶۷۸۹").as_deref(), Some("09123456789"));
        assert_eq!(normalize_phone("(021) 4428-0505").as_deref(), Some("02144280505"));
        assert_eq!(normalize_phone("+98 912 345 6789").as_deref(), Some("+989123456789"));
        assert_eq!(normalize_phone("12"), None);
        assert_eq!(normalize_phone("0912abc4567"), None);
    }

    #[test]
    fn the_form_needs_a_name_and_a_phone() {
        assert_eq!(check("  خانم   رضایی ", "09123456789", " چاپگر ").unwrap(), ("خانم رضایی".to_owned(), "09123456789".to_owned(), "چاپگر".to_owned()));
        assert!(check("", "09123456789", "").is_err());
        assert!(check("علی", "123", "").is_err());
        assert!(check(&"ن".repeat(61), "09123456789", "").is_err());
        assert_eq!(check("علی", "09123456789", &"x".repeat(600)).unwrap().2.len(), 500);
    }

    #[test]
    fn answers_become_persian_text_with_the_request_number() {
        let (ok, text) = answer_text(200, r#"{"ok":true,"number":123}"#);
        assert!(ok);
        assert!(text.contains("۱۲۳"));
        let (ok, text) = answer_text(200, r#"{"ok":false,"reason":"already","number":45}"#);
        assert!(ok);
        assert!(text.contains("۴۵") && text.contains("در صف"));
        assert!(!answer_text(200, r#"{"ok":false,"reason":"not_linked"}"#).0);
        assert!(!answer_text(200, r#"{"ok":false,"reason":"stale"}"#).0);
        assert_eq!(answer_text(502, "<html>").1, NETWORK_TEXT);
        assert!(answer_text(429, "").1.contains("چند دقیقه"));
    }
}
