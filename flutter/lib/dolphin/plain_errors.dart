/// DD-13: plain Persian for the errors a technician or customer can hit that are not translation keys: Windows file and
/// socket errors arrive as the OS's own text ("Access is denied. (os error 5)", or the same in the PC's language), so
/// the fa.rs overlay (dolphin/rebrand.py FA_ERRORS, FA_ADD) cannot reach them. Each text says what happened and what to
/// do. Matched by the Windows error code first, then by upstream's English wording for the same errors.

class _Plain {
  final List<int> codes;
  final List<String> english;
  final String text;
  const _Plain(this.codes, this.english, this.text);
}

const _plain = <_Plain>[
  // Files (both directions of a transfer).
  _Plain([5], ['access is denied', 'permission denied'],
      'اجازه‌ی دسترسی به این فایل یا پوشه نیست؛ پوشه‌ی دیگری، مثلاً «دریافتی دلفین»، را انتخاب کنید.'),
  _Plain([32, 33, 1224], ['being used by another process', 'locked a portion of the file'],
      'این فایل در برنامه‌ی دیگری باز است؛ آن برنامه را ببندید و دوباره بفرستید.'),
  _Plain([39, 112], ['not enough space on the disk', 'no space left on device', 'disk is full'],
      'جای خالی دیسک تمام شده است؛ جا باز کنید یا پوشه‌ای روی دیسک دیگر را انتخاب کنید.'),
  _Plain([2, 3], ['cannot find the file', 'cannot find the path', 'no such file or directory'],
      'فایل یا پوشه پیدا نشد؛ شاید جابه‌جا یا پاک شده است. فهرست را تازه کنید.'),
  _Plain([80, 183], ['file exists', 'already exists'],
      'فایلی با همین نام آنجا هست؛ نام را عوض کنید یا پوشه‌ی دیگری را انتخاب کنید.'),
  _Plain([206], ['filename or extension is too long'],
      'نام یا مسیر فایل خیلی بلند است؛ آن را در پوشه‌ای با مسیر کوتاه‌تر بگذارید.'),
  _Plain([123], ['syntax is incorrect'], 'این نام در ویندوز مجاز نیست؛ نام فایل یا پوشه را عوض کنید.'),
  _Plain([19], ['write protected', 'read-only file system'], 'این دیسک فقط‌خواندنی است؛ پوشه‌ی دیگری را انتخاب کنید.'),
  _Plain([21], ['device is not ready'], 'دیسک آماده نیست (مثلاً فلش بیرون آمده است)؛ دوباره وصل کنید و از نو بفرستید.'),
  // Connections.
  _Plain([10060], ['timed out'],
      'پاسخی نیامد؛ اینترنت یا VPN هر دو طرف را بررسی کنید و دوباره وصل شوید.'),
  _Plain([10061], ['connection refused', 'actively refused'],
      'رایانه‌ی مقصد اتصال را نپذیرفت؛ دوباره تلاش کنید و اگر تکرار شد با پشتیبانی دلفین تماس بگیرید.'),
  _Plain([10053, 10054], ['forcibly closed', 'connection reset', 'connection aborted', 'broken pipe'],
      'اتصال در میانه قطع شد؛ اینترنت را بررسی کنید و دوباره وصل شوید.'),
  _Plain([10050, 10051, 10065], ['network is unreachable', 'host is unreachable', 'network is down'],
      'شبکه در دسترس نیست؛ اینترنت این رایانه را بررسی کنید.'),
  _Plain([11001, 11002, 11004], ['no such host', 'failed to lookup address', 'name or service not known'],
      'نشانی سرور دلفین پیدا نشد؛ اینترنت یا DNS را بررسی کنید.'),
];

/// Windows error codes the table covers (for the test that each has a text).
List<int> get dolphinPlainErrorCodes => [for (final p in _plain) ...p.codes];

final _osError = RegExp(r'os error (\d+)');

/// The plain text for [raw] (an OS error as upstream reports it, alone or after "Failed …: "), or null to leave the
/// message to upstream. The code is kept at the end, in Latin digits, for support.
String? dolphinPlainError(String raw) {
  final m = _osError.firstMatch(raw);
  if (m != null) {
    final code = int.parse(m.group(1)!);
    for (final p in _plain) {
      if (p.codes.contains(code)) return '${p.text} (کد $code)';
    }
  }
  final t = raw.toLowerCase();
  for (final p in _plain) {
    if (p.english.any(t.contains)) return p.text;
  }
  return null;
}
