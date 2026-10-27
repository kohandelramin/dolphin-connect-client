const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

/// Latin digits to Persian, for display only (the portal's lib/fa.ts toPersianDigits).
String faDigits(String s) => s.replaceAllMapped(RegExp(r'[0-9]'), (m) => _persianDigits[int.parse(m[0]!)]);

/// «نسخه‌ی ۲.۰.۰»: Dolphin's own version (TB-4), never RustDesk's 1.5.0.
String versionLabel(String version) => 'نسخه‌ی ${faDigits(version)}';
