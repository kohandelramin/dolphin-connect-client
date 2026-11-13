import '../digits.dart';
import '../home_view.dart' show groupId;

/// Plan 19, the native technician screens: how times, dates and IDs read. Pure, so every rule is unit-tested
/// (test/dolphin/tech_ui/format_test.dart). The API gives ISO times (UTC); everything here shows the PC's own clock.

/// The ID as the screens show it: Persian digits in groups of three, e.g. «۱۹۴ ۰۵۲ ۳۶۱» (shown left to right).
String idFa(String id) => faDigits(groupId(id));

String _two(int n) => n.toString().padLeft(2, '0');

/// «۱۰:۴۲» in this PC's clock.
String clockFa(DateTime t) {
  final l = t.toLocal();
  return faDigits('${_two(l.hour)}:${_two(l.minute)}');
}

/// A session's length: «۰۷:۱۲», or «۱:۰۷:۱۲» past an hour.
String elapsedFa(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  return faDigits(h > 0 ? '$h:${_two(m)}:${_two(sec)}' : '${_two(m)}:${_two(sec)}');
}

const kJalaliMonths = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

/// The Jalali (Solar Hijri) date of a Gregorian day: (year, month 1–12, day). The arithmetic of jalaali-js (the same
/// calendar date-fns-jalali uses on the portal).
(int, int, int) toJalali(int gy, int gm, int gd) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 + 365 * gy + (gy2 + 3) ~/ 4 - (gy2 + 99) ~/ 100 + (gy2 + 399) ~/ 400 + gd + gdm[gm - 1];
  var jy = -1595 + 33 * (days ~/ 12053);
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final int jm, jd;
  if (days < 186) {
    jm = 1 + days ~/ 31;
    jd = 1 + days % 31;
  } else {
    jm = 7 + (days - 186) ~/ 30;
    jd = 1 + (days - 186) % 30;
  }
  return (jy, jm, jd);
}

/// «۶ آبان», with the year when it is not this Jalali year («۶ آبان ۱۴۰۴»).
String jalaliFa(DateTime t, DateTime now) {
  final l = t.toLocal(), n = now.toLocal();
  final (y, m, d) = toJalali(l.year, l.month, l.day);
  final (ny, _, _) = toJalali(n.year, n.month, n.day);
  return faDigits(y == ny ? '$d ${kJalaliMonths[m - 1]}' : '$d ${kJalaliMonths[m - 1]} $y');
}

int _daysBetween(DateTime a, DateTime b) {
  final da = DateTime(a.year, a.month, a.day), db = DateTime(b.year, b.month, b.day);
  return db.difference(da).inHours ~/ 24;
}

/// «همین حالا», «۱۰ دقیقه پیش», «۳ ساعت پیش», «دیروز», «۳ روز پیش», «هفته‌ی پیش», then the Jalali date.
String agoFa(DateTime at, DateTime now) {
  final l = at.toLocal(), n = now.toLocal();
  final diff = n.difference(l);
  if (diff.inMinutes < 1) return 'همین حالا';
  if (diff.inMinutes < 60) return '${faDigits('${diff.inMinutes}')} دقیقه پیش';
  final days = _daysBetween(l, n);
  if (days <= 0) return '${faDigits('${diff.inHours}')} ساعت پیش';
  if (days == 1) return 'دیروز';
  if (days < 7) return '${faDigits('$days')} روز پیش';
  if (days < 14) return 'هفته‌ی پیش';
  return jalaliFa(l, n);
}

/// «امروز ۱۸:۴۳», «دیروز ۰۹:۱۰», or «۶ آبان ۱۸:۴۳».
String dayTimeFa(DateTime at, DateTime now) {
  final l = at.toLocal(), n = now.toLocal();
  final days = _daysBetween(l, n);
  final day = days == 0
      ? 'امروز'
      : days == 1
          ? 'دیروز'
          : jalaliFa(l, n);
  return '$day ${clockFa(l)}';
}

/// How long a request has waited: «۱۲ دقیقه», «۲ ساعت», «۳ روز».
String waitedFa(DateTime since, DateTime now) {
  final d = now.difference(since);
  if (d.inMinutes < 1) return 'کمتر از یک دقیقه';
  if (d.inMinutes < 60) return '${faDigits('${d.inMinutes}')} دقیقه';
  if (d.inHours < 24) return '${faDigits('${d.inHours}')} ساعت';
  return '${faDigits('${d.inDays}')} روز';
}

/// A request that has waited this long is shown in amber (T3: «قدیمی‌ها نارنجی»).
const kOldRequest = Duration(minutes: 10);

bool isOldRequest(DateTime since, DateTime now) => now.difference(since) >= kOldRequest;

/// File sizes in the card: «۱٫۲ مگابایت», «۳۴۰ کیلوبایت».
String sizeFa(int bytes) {
  if (bytes >= 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    return '${faDigits(mb.toStringAsFixed(1)).replaceAll('.', '٫')} مگابایت';
  }
  final kb = (bytes / 1024).ceil();
  return '${faDigits('$kb')} کیلوبایت';
}

/// The Windows name the PC reported, in Persian where it is plain: "Windows 11 Pro" → «ویندوز ۱۱ Pro».
String osFa(String? os) {
  final s = (os ?? '').trim();
  if (s.isEmpty) return '';
  return faDigits(s.replaceFirst(RegExp('^Windows', caseSensitive: false), 'ویندوز'));
}

/// «برنامه ۲.۱.۰».
String appVersionFa(String? v) => (v ?? '').trim().isEmpty ? '' : 'برنامه ${faDigits(v!.trim())}';
