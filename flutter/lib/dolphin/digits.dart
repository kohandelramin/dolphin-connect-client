const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

/// Latin digits to Persian, for display only (the portal's lib/fa.ts toPersianDigits).
String faDigits(String s) => s.replaceAllMapped(RegExp(r'[0-9]'), (m) => _persianDigits[int.parse(m[0]!)]);

/// «نسخه‌ی ۲.۰.۰»: Dolphin's own version (TB-4), never RustDesk's 1.5.0.
String versionLabel(String version) => 'نسخه‌ی ${faDigits(version)}';

const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

/// Persian and Arabic-Indic digits back to Latin. What goes on the clipboard is always Latin (DD-44): the
/// technician's ID field and the portal's forms take Latin digits.
String latinDigits(String s) => s.replaceAllMapped(RegExp('[۰-۹٠-٩]'), (m) {
      final c = m[0]!;
      final i = _persianDigits.indexOf(c);
      return '${i >= 0 ? i : _arabicDigits.indexOf(c)}';
    });

/// The ID as it goes on the clipboard: Latin digits, no group spaces (DD-44).
String idForClipboard(String shown) => latinDigits(shown).replaceAll(RegExp(r'\s'), '');
