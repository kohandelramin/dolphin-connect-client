import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_hbb/dolphin/update_view.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) =>
    MaterialApp(theme: dolphinTheme(ThemeData.light()), home: Scaffold(body: child));

const _phone = 'اگر درست نشد با پشتیبانی دلفین تماس بگیرید: ۰۲۱-۴۴۲۰۰۲۵۰';
const _update = DolphinUpdateCheck(
    state: 'update',
    version: '2.0.1',
    lead: 'نسخه‌ی ۲.۰.۱ آماده است.',
    phone: _phone,
    downloadPage: 'https://support.dolphindev.ir/download');

Widget _view(DolphinUpdateCheck check, DolphinUpdateProgress progress,
        {VoidCallback? retry, VoidCallback? page, VoidCallback? onContinue}) =>
    _app(DolphinUpdateView(
        check: check,
        progress: progress,
        onRetry: retry ?? () {},
        onDownloadPage: page ?? () {},
        onContinue: onContinue ?? () {},
        onClose: () {}));

void main() {
  test('an unreadable or current answer opens the app (D12)', () {
    for (final raw in ['', 'nope', '[1]', '{"state":"current"}', '{"state":"surprise"}', '{"state":3}']) {
      expect(DolphinUpdateCheck.fromJson(raw).blocksStart, isFalse, reason: raw);
    }
  });

  test('update, manual and blocked keep the app closed (D10)', () {
    final c = DolphinUpdateCheck.fromJson(
        '{"state":"update","version":"2.0.1","lead":"x","error":"","phone":"p","downloadPage":"https://support.dolphindev.ir/download"}');
    expect(c.blocksStart, isTrue);
    expect([c.version, c.lead, c.phone, c.downloadPage], ['2.0.1', 'x', 'p', 'https://support.dolphindev.ir/download']);
    expect(DolphinUpdateCheck.fromJson('{"state":"manual"}').blocksStart, isTrue);
    expect(DolphinUpdateCheck.fromJson('{"state":"blocked"}').blocksStart, isTrue);
  });

  test('progress parses and clamps the percentage', () {
    final p = DolphinUpdateProgress.fromJson('{"state":"downloading","percent":140,"text":"t","error":""}');
    expect([p.state, p.percent, p.text], ['downloading', 100, 't']);
    expect(DolphinUpdateProgress.fromJson('nope').state, 'idle');
  });

  testWidgets('downloading shows the title, the bar and the megabytes, no buttons', (tester) async {
    await tester.pumpWidget(_view(_update,
        const DolphinUpdateProgress(state: 'downloading', percent: 48, text: '۱۲٫۰ از ۲۴٫۶ مگابایت')));
    expect(find.text(kDolphinUpdateTitle), findsOneWidget);
    expect(find.text('۱۲٫۰ از ۲۴٫۶ مگابایت'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.48, 0.001));
    expect(find.text('تلاش دوباره'), findsNothing);
  });

  testWidgets('a failed download shows why, the phone, retry and the manual download', (tester) async {
    var retried = false;
    var opened = false;
    await tester.pumpWidget(_view(
        _update,
        const DolphinUpdateProgress(
            state: 'failed', error: 'فایل دریافت‌شده با نسخه‌ی دلفین یکی نبود و کنار گذاشته شد. برنامه‌ی شما تغییری نکرد.'),
        retry: () => retried = true,
        page: () => opened = true));
    expect(find.textContaining('یکی نبود'), findsOneWidget);
    expect(find.text(_phone), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('تلاش دوباره'));
    await tester.tap(find.text('دریافت دستی'));
    expect([retried, opened], [true, true]);
  });

  testWidgets('blocked shows its own error before anything is retried', (tester) async {
    const blocked = DolphinUpdateCheck(
        state: 'blocked', version: '2.0.1', lead: 'l', error: 'به‌روزرسانی خودکار چند دقیقه پیش انجام نشد.', phone: _phone);
    await tester.pumpWidget(_view(blocked, DolphinUpdateProgress.idle));
    expect(find.text('به‌روزرسانی خودکار چند دقیقه پیش انجام نشد.'), findsOneWidget);
    expect(find.text('تلاش دوباره'), findsOneWidget);
  });

  testWidgets('the technician app is sent to the panel to download (D13)', (tester) async {
    var opened = false;
    const manual = DolphinUpdateCheck(state: 'manual', version: '2.0.1', lead: 'از پنل دلفین دریافت کنید');
    await tester.pumpWidget(_view(manual, DolphinUpdateProgress.idle, page: () => opened = true));
    expect(find.text('تلاش دوباره'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('دریافت دستی'));
    expect(opened, isTrue);
  });

  // D19: after a failure the customer may continue with the current version, for this run only.
  testWidgets('a failed update offers to continue with this version', (tester) async {
    var continued = false;
    await tester.pumpWidget(_view(
        _update, const DolphinUpdateProgress(state: 'failed', error: 'دریافت نشد.'),
        onContinue: () => continued = true));
    await tester.tap(find.text('ادامه با همین نسخه'));
    expect(continued, isTrue);
    expect(find.text('تلاش دوباره'), findsOneWidget);
  });

  testWidgets('blocked offers to continue; update, downloading, ready, applying and manual do not', (tester) async {
    const blocked = DolphinUpdateCheck(state: 'blocked', version: '2.0.1', error: 'e', phone: _phone);
    await tester.pumpWidget(_view(blocked, DolphinUpdateProgress.idle));
    expect(find.text('ادامه با همین نسخه'), findsOneWidget);
    for (final p in [
      DolphinUpdateProgress.idle,
      const DolphinUpdateProgress(state: 'downloading', percent: 10, text: 't'),
      const DolphinUpdateProgress(state: 'ready'),
      const DolphinUpdateProgress(state: 'applying'),
    ]) {
      await tester.pumpWidget(_view(_update, p));
      expect(find.text('ادامه با همین نسخه'), findsNothing, reason: p.state);
    }
    const manual = DolphinUpdateCheck(state: 'manual', version: '2.0.1', lead: 'l');
    await tester.pumpWidget(_view(manual, DolphinUpdateProgress.idle));
    expect(find.text('ادامه با همین نسخه'), findsNothing);
  });

  testWidgets('applying is a bar and a message, never a failure', (tester) async {
    await tester.pumpWidget(_view(_update, const DolphinUpdateProgress(state: 'applying')));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('در حال نصب…'), findsOneWidget);
    expect(find.text('تلاش دوباره'), findsNothing);
  });

  testWidgets('ready says the same as applying (one text in both screens)', (tester) async {
    await tester.pumpWidget(_view(_update, const DolphinUpdateProgress(state: 'ready')));
    expect(find.text('در حال نصب…'), findsOneWidget);
  });

  // I3: a session is live, so the install waits for it; nothing on screen can cut the session.
  testWidgets('waiting for a session to end says so and offers no button', (tester) async {
    await tester.pumpWidget(_view(_update, const DolphinUpdateProgress(state: 'ready', waiting: true)));
    expect(find.text('پس از پایان جلسه نصب می‌شود.'), findsOneWidget);
    expect(find.text('در حال نصب…'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(DolphinUpdateProgress.fromJson('{"state":"ready","waiting":true}').waiting, isTrue);
    expect(DolphinUpdateProgress.fromJson('{"state":"ready"}').waiting, isFalse);
    expect(DolphinUpdateProgress.fromJson('{"state":"ready","waiting":"yes"}').waiting, isFalse);
  });

  // Both screens: retry, then continue, then the manual download, then close (review minors).
  testWidgets('the buttons come in the same order as the Sciter screen', (tester) async {
    await tester.pumpWidget(_view(_update, const DolphinUpdateProgress(state: 'failed', error: 'e')));
    final xs = ['تلاش دوباره', 'ادامه با همین نسخه', 'دریافت دستی', 'بستن']
        .map((t) => tester.getCenter(find.text(t)).dx)
        .toList();
    // RTL: the first button is the right-most one.
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i] < xs[i - 1], isTrue, reason: 'button $i should be left of button ${i - 1}: $xs');
    }
  });

  testWidgets('without an onContinue handler there is no button', (tester) async {
    await tester.pumpWidget(_app(DolphinUpdateView(
        check: _update,
        progress: const DolphinUpdateProgress(state: 'failed', error: 'e'),
        onRetry: () {},
        onDownloadPage: () {},
        onClose: () {})));
    expect(find.text('ادامه با همین نسخه'), findsNothing);
  });
}
