import '../customer_api/api.dart';
import '../digits.dart';
import '../tech_ui/format.dart' show clockFa, jalaliFa;

export '../tech_ui/format.dart' show clockFa, dayTimeFa, idFa, jalaliFa, sizeFa;

/// Plan 19 C4: how the customer's requests read. Pure, so every rule is unit-tested (test/dolphin/customer_c4_test.dart).

/// «#۱۲۴».
String requestNumberFa(int n) => '#${faDigits('$n')}';

/// The approved design's words for the two states it draws (C4.2: «در صف», «در حال بررسی»); the portal's for the rest.
String statusLabel(String status) => switch (status) {
      'submitted' => 'در صف',
      'claimed' => 'در حال بررسی',
      'in_session' => 'در جلسه',
      'resolved' => 'حل‌شده',
      'cancelled' => 'لغوشده',
      _ => status,
    };

enum StatusTone { neutral, active, done }

StatusTone statusTone(String status) => switch (status) {
      'claimed' || 'in_session' => StatusTone.active,
      'resolved' => StatusTone.done,
      _ => StatusTone.neutral,
    };

int _daysBetween(DateTime a, DateTime b) {
  final da = DateTime(a.year, a.month, a.day), db = DateTime(b.year, b.month, b.day);
  return db.difference(da).inHours ~/ 24;
}

/// A short time in a list: «۱۰:۴۲» today, «دیروز», then the Jalali day.
String shortTimeFa(DateTime at, DateTime now) {
  final l = at.toLocal(), n = now.toLocal();
  final days = _daysBetween(l, n);
  if (days <= 0) return clockFa(l);
  if (days == 1) return 'دیروز';
  return jalaliFa(l, n);
}

/// A message body cut for one line, with «…» when cut.
String snippet(String body, [int max = 60]) {
  final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = flat.runes.toList();
  return runes.length <= max ? flat : '${String.fromCharCodes(runes.take(max))}…';
}

/// The third line of a row (design C4.2): «علی رضایی: «ساعت ۱۱ وصل می‌شوم…» · ۱۰:۴۲», or «ثبت شد · دیروز».
String lastLine(CustomerRequestRow r, DateTime now) {
  final m = r.lastMessage;
  if (m == null) return 'ثبت شد · ${shortTimeFa(r.updatedAt, now)}';
  final who = m.fromStaff ? (m.authorName.isEmpty ? 'دلفین' : m.authorName) : 'شما';
  return '$who: «${snippet(m.body)}» · ${shortTimeFa(m.at, now)}';
}

/// The second line: «#۱۲۴ · نرم‌افزار حسابداری».
String metaLine(CustomerRequestRow r) =>
    [requestNumberFa(r.number), if ((r.product ?? '').trim().isNotEmpty) r.product!.trim()].join(' · ');

/// The red count on the main window's row: «۳», «۹۹+».
String unreadBadge(int n) => n > 99 ? '${faDigits('99')}+' : faDigits('$n');
