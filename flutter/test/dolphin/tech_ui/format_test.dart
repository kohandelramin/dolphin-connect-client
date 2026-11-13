import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:flutter_hbb/dolphin/tech_ui/format.dart';
import 'package:flutter_hbb/dolphin/tech_ui/pc_card.dart' show historyLine;
import 'package:flutter_hbb/dolphin/tech_ui/requests.dart' show requestSource;
import 'package:flutter_hbb/dolphin/tech_ui/shell_model.dart' show cleanTypedId, wakePageUrl;
import 'package:flutter_hbb/dolphin/tech_ui/widgets.dart';
import 'package:flutter_hbb/dolphin/theme_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Jalali dates', () {
    test('known days convert as the portal\'s calendar does', () {
      expect(toJalali(2026, 3, 21), (1405, 1, 1)); // Nowruz 1405
      expect(toJalali(2026, 11, 14), (1405, 8, 23));
      expect(toJalali(2025, 3, 20), (1403, 12, 30)); // the last day of leap 1403
      expect(toJalali(2024, 2, 29), (1402, 12, 10));
      expect(toJalali(2026, 10, 23), (1405, 8, 1));
    });

    test('«۶ آبان», with the year only when it is another year', () {
      final now = DateTime(2026, 11, 14, 12);
      expect(jalaliFa(DateTime(2026, 10, 28, 9), now), '۶ آبان');
      expect(jalaliFa(DateTime(2025, 10, 28, 9), now), '۶ آبان ۱۴۰۴');
    });
  });

  test('ago: minutes, hours, yesterday, days, last week, then the date', () {
    final now = DateTime(2026, 11, 14, 12);
    expect(agoFa(now.subtract(const Duration(seconds: 20)), now), 'همین حالا');
    expect(agoFa(now.subtract(const Duration(minutes: 10)), now), '۱۰ دقیقه پیش');
    expect(agoFa(now.subtract(const Duration(hours: 3)), now), '۳ ساعت پیش');
    expect(agoFa(DateTime(2026, 11, 13, 23), now), 'دیروز');
    expect(agoFa(DateTime(2026, 11, 11, 9), now), '۳ روز پیش');
    expect(agoFa(DateTime(2026, 11, 5, 9), now), 'هفته‌ی پیش');
    expect(agoFa(DateTime(2026, 10, 28, 9), now), '۶ آبان');
  });

  test('day and time, waited, clock, elapsed, sizes, ID', () {
    final now = DateTime(2026, 11, 14, 19);
    expect(dayTimeFa(DateTime(2026, 11, 14, 18, 43), now), 'امروز ۱۸:۴۳');
    expect(dayTimeFa(DateTime(2026, 11, 13, 9, 5), now), 'دیروز ۰۹:۰۵');
    expect(waitedFa(now.subtract(const Duration(minutes: 12)), now), '۱۲ دقیقه');
    expect(waitedFa(now.subtract(const Duration(hours: 2, minutes: 5)), now), '۲ ساعت');
    expect(isOldRequest(now.subtract(const Duration(minutes: 9)), now), isFalse);
    expect(isOldRequest(now.subtract(const Duration(minutes: 10)), now), isTrue);
    expect(clockFa(DateTime(2026, 11, 14, 10, 42)), '۱۰:۴۲');
    expect(elapsedFa(const Duration(minutes: 7, seconds: 12)), '۰۷:۱۲');
    expect(elapsedFa(const Duration(hours: 1, minutes: 2, seconds: 3)), '۱:۰۲:۰۳');
    expect(sizeFa(284000), '۲۷۸ کیلوبایت');
    expect(sizeFa(1300000), '۱٫۲ مگابایت');
    expect(idFa('194052361'), '۱۹۴ ۰۵۲ ۳۶۱');
    expect(osFa('Windows 11 Pro'), 'ویندوز ۱۱ Pro');
    expect(appVersionFa('2.1.0'), 'برنامه ۲.۱.۰');
  });

  test('typed IDs: spaces, dashes and Persian digits are fine; anything else is not an ID', () {
    expect(cleanTypedId('194 052 361'), '194052361');
    expect(cleanTypedId('۱۹۴-۰۵۲-۳۶۱'), '194052361');
    expect(cleanTypedId('12'), isNull);
    expect(cleanTypedId('abc'), isNull);
  });

  test('«روشن کن» opens the PC\'s page on the portal', () {
    expect(wakePageUrl('pc-1'), endsWith('/staff/computers/pc-1'));
  });

  test('a tile\'s colour keeps white text at AA whatever the organization\'s colour is', () {
    for (final hex in ['#1d4ed8', '#0f766e', '#c2410c', '#7c3aed', '#facc15', '#ffffff', '#a3e635', '#000000']) {
      final c = tileColorFor(parseHexColor(hex));
      expect(contrastRatio(Colors.white, c), greaterThanOrEqualTo(4.5), reason: hex);
    }
    // A dark colour is used as it is.
    expect(tileColorFor(parseHexColor('#1d4ed8')), const Color(0xFF1D4ED8));
  });

  test('PC state: in someone else\'s session, online, off, unknown from the cache', () {
    const org = OrgRef('o', 'گردش‌کار', '#1d4ed8');
    expect(pcStateOf(const Computer(id: 'a', rustdeskId: '1', organization: org, online: true)), PcState.online);
    expect(pcStateOf(const Computer(id: 'a', rustdeskId: '1', organization: org)), PcState.offline);
    expect(
        pcStateOf(const Computer(id: 'a', rustdeskId: '1', organization: org, online: true, session: PcSession('مریم', false, null))),
        PcState.busy);
    expect(
        pcStateOf(const Computer(id: 'a', rustdeskId: '1', organization: org, online: true, session: PcSession('من', true, null))),
        PcState.online);
    expect(pcStateOf(const Computer(id: 'a', rustdeskId: '1', organization: org, fromCache: true)), PcState.unknown);
  });

  test('history lines and request sources read in Persian', () {
    final now = DateTime(2026, 11, 14, 12);
    expect(
        historyLine(
            HistoryRequest(DateTime(2026, 10, 28, 9), 'PC-1',
                id: 'h', number: 1, subject: 'تماس تلفنی', openedBy: 'staff', status: 'resolved', assigneeName: 'مدیر'),
            now),
        'تماس تلفنی · ۶ آبان · مدیر · حل‌شده');
    expect(
        historyLine(
            HistoryConnection(DateTime(2026, 11, 13, 9, 0), 'PC-1',
                id: 1, technician: 'علی', verified: true, closedAt: DateTime(2026, 11, 13, 9, 12), files: 2),
            now),
        'اتصال · دیروز ۰۹:۰۰ · علی · ۱۲ دقیقه · ۲ فایل');
    RequestRow row(String by) => RequestRow(
        id: 'r',
        number: 1,
        subject: 's',
        status: 'open',
        priority: 'normal',
        openedBy: by,
        kind: 'support',
        organization: const OrgRef('o', 'n', '#000000'),
        mine: false,
        createdAt: now);
    expect(requestSource(row('app')), '«با من تماس بگیرید» از برنامه');
    expect(requestSource(row('customer')), 'از پورتال مشتری');
    expect(requestSource(row('staff')), 'ثبت کارشناس');
  });
}
