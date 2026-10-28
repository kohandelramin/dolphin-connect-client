import 'package:flutter_hbb/dolphin/recent_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the pushed list and drops anything unexpected (UN-15)', () {
    expect(parseRecentSessions('-'), isEmpty);
    expect(parseRecentSessions('not json'), isEmpty);
    expect(parseRecentSessions('{"t":1}'), isEmpty);
    final list = parseRecentSessions('[{"t":1793001600,"m":12,"n":"علی"},{"t":"x","m":1,"n":""},{"t":1793001600,"m":0,"n":""}]');
    expect(list.length, 1);
    expect(list.first.minutes, 12);
    expect(list.first.name, 'علی');
  });

  test('says who, when and how long in Persian; an unnamed technician is «ناشناس»', () {
    final now = DateTime(2026, 10, 28, 15, 0);
    expect(recentLine(RecentSession(DateTime(2026, 10, 28, 11, 30), 12, 'علی'), now), 'علی · امروز ۱۱:۳۰ · ۱۲ دقیقه');
    expect(recentLine(RecentSession(DateTime(2026, 10, 27, 9, 5), 75, ''), now), 'ناشناس · دیروز ۰۹:۰۵ · ۱ ساعت و ۱۵ دقیقه');
    expect(recentLine(RecentSession(DateTime(2026, 10, 24, 9, 5), 3, 'سارا'), now), 'سارا · ۴ روز پیش ۰۹:۰۵ · ۳ دقیقه');
  });
}
