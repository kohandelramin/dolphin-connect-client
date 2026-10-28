import 'dart:convert';

import 'digits.dart';

/// Pushed by the portal (app/src/lib/engine/policy.ts RECENT_SESSIONS_OPTION): the last finished sessions on this PC
/// (UN-15), so a customer without a portal account still sees who connected and for how long.
const kDolphinRecentSessionsOption = 'dolphin-recent-sessions';

class RecentSession {
  final DateTime start;
  final int minutes;

  /// A technician registered with Dolphin, or '' when the portal could not name one.
  final String name;
  const RecentSession(this.start, this.minutes, this.name);
}

/// The option's JSON, newest first. Anything unexpected (missing, "-", bad JSON, wrong types) gives an empty list.
List<RecentSession> parseRecentSessions(String raw) {
  try {
    final data = jsonDecode(raw);
    if (data is! List) return const [];
    final out = <RecentSession>[];
    for (final item in data.take(5)) {
      if (item is! Map) continue;
      final t = item['t'], m = item['m'], n = item['n'];
      if (t is! int || m is! int || n is! String || m < 1) continue;
      out.add(RecentSession(DateTime.fromMillisecondsSinceEpoch(t * 1000), m, n.length > 60 ? n.substring(0, 60) : n));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// «علی · امروز ۱۱:۳۰ · ۱۲ دقیقه». Days relative to `now`, in this PC's own clock.
String recentLine(RecentSession s, DateTime now) {
  final local = s.start.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  final when = days <= 0
      ? 'امروز'
      : days == 1
          ? 'دیروز'
          : '${faDigits('$days')} روز پیش';
  final who = s.name.isEmpty ? 'ناشناس' : s.name;
  final length = s.minutes < 60
      ? '${faDigits('${s.minutes}')} دقیقه'
      : '${faDigits('${s.minutes ~/ 60}')} ساعت و ${faDigits('${s.minutes % 60}')} دقیقه';
  return '$who · $when ${faDigits('${_two(local.hour)}:${_two(local.minute)}')} · $length';
}
