import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/access_profile.dart';
import 'package:flutter_hbb/dolphin/connection_view.dart';
import 'package:flutter_hbb/dolphin/customer_settings.dart';
import 'package:flutter_hbb/dolphin/demo.dart';
import 'package:flutter_hbb/dolphin/first_run_view.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/network_status.dart';
import 'package:flutter_hbb/dolphin/session_frame.dart';
import 'package:flutter_hbb/dolphin/share.dart';
import 'package:flutter_hbb/dolphin/switches.dart';
import 'package:flutter_hbb/dolphin/tech_card.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_hbb/dolphin/theme_tokens.dart' show ThemeOverrideResult;
import 'package:flutter_hbb/dolphin/update_check.dart';
import 'package:flutter_hbb/dolphin/verify.dart';
import 'package:flutter_hbb/dolphin/window_sizes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// Plan 19, the customer app's new look (C1–C7, approved 2026-11-14): profiles, settings, the session frame, the
// customer's light and dark, the window sizes, and every new view readable in both.

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

/// Pumps [child] at exactly [size] (the window's size), in the customer's light or dark.
Future<void> _at(WidgetTester tester, Size size, Widget child, {bool dark = false}) async {
  DolphinCustomerTheme.apply(dark ? DolphinThemeChoice.dark : DolphinThemeChoice.light, platform: Brightness.light);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(_app(child));
}

const _ali = TechVerdict(TechCheck.verified, 'علی رضایی');

DolphinHomeView _main({VoidCallback? onSettings, DolphinServerState state = DolphinServerState.ready, int? connected = 0}) =>
    DolphinHomeView(
      id: '123456789',
      state: state,
      connected: connected,
      coming: connected == 1 ? const TechComing('علی رضایی', null) : null,
      onCopy: () {},
      phone: '021-44280505',
      siteLabel: 'support.dolphindev.ir',
      network: networkRows(server: state, localIp: '192.168.1.24'),
      version: '2.2.0',
      onHealth: () {},
      onReport: () {},
      onScreenshot: () {},
      share: DolphinShareView(stopped: false, onToggle: () {}),
      onSettings: onSettings ?? () {},
      onAbout: () {},
    );

DolphinCustomerSettingsView _settings(
        {bool ask = true,
        ValueChanged<bool>? onAsk,
        bool frame = false,
        ValueChanged<bool>? onFrame,
        String folder = r'C:\Users\Ali\Downloads\دریافتی دلفین',
        ValueChanged<DolphinThemeChoice>? onTheme,
        bool locked = false}) =>
    DolphinCustomerSettingsView(
      askOnClose: ask,
      onAskOnClose: locked ? null : (onAsk ?? (_) {}),
      frame: frame,
      onFrame: onFrame ?? (_) {},
      receiveFolder: folder,
      onOpenFolder: () {},
      theme: DolphinThemeChoice.system,
      onTheme: onTheme ?? (_) {},
      updateCheck: DolphinUpdateCheckView(phase: UpdateCheckPhase.idle, onCheck: () {}, onUpdate: () {}),
      onClose: () {},
    );

void main() {
  tearDown(DolphinCustomerTheme.reset);

  group('C2 profiles (pure)', () {
    test('«کامل» turns the three on and keeps sound off; «فقط تماشا» turns everything off', () {
      expect(DolphinGrant.full, const DolphinGrant(keyboard: true, clipboard: true, file: true, audio: false));
      expect(DolphinGrant.viewOnly, const DolphinGrant(keyboard: false, clipboard: false, file: false, audio: false));
      expect(DolphinGrant.initial, DolphinGrant.full);
      final withSound = DolphinGrant.full.copyWith(audio: true);
      expect(grantFor(DolphinProfile.viewOnly, withSound), DolphinGrant.viewOnly); // sound off too
      expect(grantFor(DolphinProfile.full, DolphinGrant.viewOnly), DolphinGrant.full); // sound stays off
      expect(grantFor(DolphinProfile.custom, withSound), withSound);
    });

    test('which segment is lit: sound is its own choice in «کامل», one key by hand is neither', () {
      expect(profileOf(DolphinGrant.full), DolphinProfile.full);
      expect(profileOf(DolphinGrant.full.copyWith(audio: true)), DolphinProfile.full);
      expect(profileOf(DolphinGrant.viewOnly), DolphinProfile.viewOnly);
      expect(profileOf(DolphinGrant.viewOnly.copyWith(audio: true)), DolphinProfile.custom);
      expect(profileOf(DolphinGrant.full.copyWith(file: false)), DolphinProfile.custom);
    });

    test('one switch by name; never sound when the organization does not offer it', () {
      final g = DolphinGrant.full.withPermission('audio', true).withPermission('clipboard', false);
      expect([for (final p in ['keyboard', 'clipboard', 'file', 'audio']) g.of(p)], [true, false, true, true]);
      expect(g.offered(sound: false).audio, isFalse);
      expect(g.offered(sound: true).audio, isTrue);
      expect(() => g.of('restart'), throwsArgumentError);
      expect(grantLabels(sound: false).map((l) => l.$1), ['keyboard', 'clipboard', 'file']);
      expect(grantLabels(sound: true).map((l) => l.$2), ['ماوس و صفحه‌کلید', 'کلیپ‌بورد', 'انتقال فایل', 'صدای رایانه']);
    });

    test('a press within 120 ms of the technician\'s last click is his, not the customer\'s', () {
      expect(clickIsLocal(pressedMs: 10000, remoteClickMs: 0), isTrue); // he never clicked
      expect(clickIsLocal(pressedMs: 10000, remoteClickMs: 9950), isFalse);
      expect(clickIsLocal(pressedMs: 10000, remoteClickMs: 9880), isFalse);
      expect(clickIsLocal(pressedMs: 10000, remoteClickMs: 9879), isTrue);
    });
  });

  group('C2 accept prompt', () {
    testWidgets('«فقط تماشا» and «کامل» set the switches; Accept passes exactly what is shown', (tester) async {
      DolphinGrant? got;
      await tester.pumpWidget(_app(DolphinAcceptView(verdict: _ali, peerName: 'x', onAccept: (g) => got = g, onDeny: () {})));
      bool sw(String p) => tester.widget<Switch>(find.byKey(ValueKey('dolphin-grant-$p'))).value;
      expect([sw('keyboard'), sw('clipboard'), sw('file'), sw('audio')], [true, true, true, false]);
      await tester.tap(find.text(kProfileViewOnlyLabel));
      await tester.pump();
      expect([sw('keyboard'), sw('clipboard'), sw('file'), sw('audio')], [false, false, false, false]);
      await tester.tap(find.byKey(const ValueKey('dolphin-accept')));
      expect(got, DolphinGrant.viewOnly);

      await tester.tap(find.text(kProfileFullLabel));
      await tester.pump();
      await tester.tap(find.text('صدای رایانه')); // the whole row is the target
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('dolphin-accept')));
      expect(got, DolphinGrant.full.copyWith(audio: true));
    });

    testWidgets('a key changed by hand lights neither profile', (tester) async {
      await tester.pumpWidget(_app(DolphinAcceptView(verdict: _ali, peerName: 'x', onAccept: (_) {}, onDeny: () {})));
      Color seg(DolphinProfile p) => tester
          .widget<Material>(find.ancestor(of: find.byKey(ValueKey('dolphin-profile-$p')), matching: find.byType(Material)).first)
          .color!;
      expect(seg(DolphinProfile.full), DolphinColors.azure);
      await tester.tap(find.text('انتقال فایل'));
      await tester.pump();
      expect(seg(DolphinProfile.full), Colors.transparent);
      expect(seg(DolphinProfile.viewOnly), Colors.transparent);
    });

    testWidgets('no sound switch when the organization hides it; the «only you» line is there', (tester) async {
      DolphinGrant? got;
      await tester.pumpWidget(_app(DolphinAcceptView(
          verdict: _ali, peerName: 'x', soundOffered: false, onAccept: (g) => got = g, onDeny: () {})));
      expect(find.text('صدای رایانه'), findsNothing);
      expect(find.text(kGrantOnlyYouLine), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dolphin-accept')));
      expect(got!.audio, isFalse);
    });

    testWidgets('the avatar shows the first letter without a photo', (tester) async {
      expect(nameInitial('علی رضایی'), 'ع');
      expect(nameInitial('  '), '');
      await tester.pumpWidget(_app(DolphinAcceptView(verdict: _ali, peerName: 'x', onAccept: (_) {}, onDeny: () {})));
      expect(find.text('ع'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);
    });
  });

  group('C3 session window', () {
    testWidgets('«… وصل است», the timer in Persian digits, the frame switch and sound only when offered', (tester) async {
      bool? frame;
      final toggled = <String, bool>{};
      await tester.pumpWidget(_app(DolphinSessionView(
          technician: 'علی رضایی',
          elapsed: const Duration(minutes: 7, seconds: 12),
          keyboard: true,
          clipboard: true,
          file: true,
          soundOffered: true,
          onToggle: (n, v) => toggled[n] = v,
          onEnd: () {},
          onFrame: (v) => frame = v)));
      expect(find.text('علی رضایی وصل است'), findsOneWidget);
      expect(find.text('۰۷:۱۲'), findsOneWidget);
      await tester.tap(find.text(kFrameLabel));
      expect(frame, isTrue);
      await tester.tap(find.text('صدای رایانه'));
      expect(toggled, {'audio': true});

      await tester.pumpWidget(_app(DolphinSessionView(
          technician: 'علی', elapsed: Duration.zero, keyboard: true, clipboard: true, file: true, onToggle: (_, __) {},
          onEnd: () {})));
      expect(find.text(kFrameLabel), findsNothing);
      expect(find.text('صدای رایانه'), findsNothing);
    });
  });

  group('C3 frame (pure)', () {
    test('off by default; only during a live session; the colour as #rrggbb', () {
      expect(frameOn(''), isFalse);
      expect(frameOn('Y'), isTrue);
      expect(frameOn('N'), isFalse);
      expect(frameValue(true), 'Y');
      expect(frameValue(false), '');
      expect(frameWanted(enabled: true, liveSession: true), isTrue);
      expect(frameWanted(enabled: true, liveSession: false), isFalse);
      expect(frameWanted(enabled: false, liveSession: true), isFalse);
      expect(frameCommand(show: true, color: const Color(0xFFE11D48)), '#e11d48');
      expect(frameCommand(show: false, color: const Color(0xFFE11D48)), '');
      // From the tokens: the danger fill, light and dark.
      expect(DolphinColors.frame, DolphinTheme.light.dangerFill);
    });
  });

  group('C5 settings', () {
    test('ask on close: on while nothing is remembered; off keeps «در دسترس بماند»; the portal can fix it', () {
      expect(closeAsks(''), isTrue);
      expect(closeAsks('stay'), isFalse);
      expect(closeAsks('quit'), isFalse);
      expect(closeAskValue(true), '');
      expect(closeAskValue(false), 'stay');
      expect(closeAskLocked(SwitchMode.available), isFalse);
      expect(closeAskLocked(SwitchMode.hidden), isTrue);
      expect(closeAskLocked(SwitchMode.forced), isTrue);
      expect(folderName(r'C:\Users\Ali\Downloads\دریافتی دلفین'), 'دریافتی دلفین');
      expect(folderName('/home/ali/x/'), 'x');
    });

    testWidgets('the switches call back, the folder row shows its name, the portal line is there', (tester) async {
      bool? ask, frame;
      await tester.pumpWidget(_app(_settings(onAsk: (v) => ask = v, onFrame: (v) => frame = v)));
      expect(find.text(kSettingsTitle), findsOneWidget);
      await tester.tap(find.text(kAskOnCloseLabel));
      expect(ask, isFalse);
      await tester.tap(find.text(kFrameSettingLabel));
      expect(frame, isTrue);
      expect(find.text('دریافتی دلفین'), findsOneWidget);
      expect(find.text(kOpenFolderLabel), findsOneWidget);
      expect(find.text(kThemeChoiceLabels[DolphinThemeChoice.system]!), findsOneWidget);
      expect(find.text(kCheckUpdateLabel), findsOneWidget);
      expect(find.text(kOrgDecidesLine), findsOneWidget);
      expect(find.text(kOrgDecidedNote), findsNothing);
    });

    testWidgets('a choice the portal fixed is dimmed with «سازمان تعیین کرده»; no folder, no row', (tester) async {
      await tester.pumpWidget(_app(_settings(locked: true, folder: '')));
      expect(find.text(kOrgDecidedNote), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const ValueKey('dolphin-settings-ask-close'))).onChanged, isNull);
      expect(find.text(kReceiveFolderRowLabel), findsNothing);
    });

    testWidgets('the theme menu offers like Windows, light and dark', (tester) async {
      DolphinThemeChoice? picked;
      await tester.pumpWidget(_app(_settings(onTheme: (c) => picked = c)));
      await tester.tap(find.byKey(const ValueKey('dolphin-settings-theme')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تیره').last);
      await tester.pumpAndSettle();
      expect(picked, DolphinThemeChoice.dark);
    });
  });

  group('C5 theme choice', () {
    test('stored values; «مثل ویندوز» is the default and follows Windows', () {
      expect(themeChoiceFrom(''), DolphinThemeChoice.system);
      expect(themeChoiceFrom('light'), DolphinThemeChoice.light);
      expect(themeChoiceFrom('dark'), DolphinThemeChoice.dark);
      expect(themeChoiceFrom('purple'), DolphinThemeChoice.system);
      expect(themeChoiceValue(DolphinThemeChoice.system), '');
      expect(themeChoiceValue(DolphinThemeChoice.dark), 'dark');
      expect(brightnessFor(DolphinThemeChoice.system, Brightness.dark), Brightness.dark);
      expect(brightnessFor(DolphinThemeChoice.light, Brightness.dark), Brightness.light);
      expect(brightnessFor(DolphinThemeChoice.dark, Brightness.light), Brightness.dark);
    });

    test('the colours follow the choice; the technician app (nothing applied) stays light', () {
      expect(DolphinColors.ground, DolphinTheme.light.background);
      DolphinCustomerTheme.apply(DolphinThemeChoice.dark, platform: Brightness.light);
      expect(DolphinColors.ground, DolphinTheme.dark.background);
      expect(DolphinColors.ink, DolphinTheme.dark.text);
      DolphinCustomerTheme.apply(DolphinThemeChoice.system, platform: Brightness.light);
      expect(DolphinColors.ground, DolphinTheme.light.background);
      DolphinCustomerTheme.reset();
      expect(DolphinColors.ground, DolphinTheme.light.background);
    });

    test('a pushed theme still reaches the customer screens, in the brightness chosen', () {
      expect(applyThemeOverrides('{"v":1,"dark":{"background":"#000000"}}'), ThemeOverrideResult.applied);
      DolphinCustomerTheme.apply(DolphinThemeChoice.dark, platform: Brightness.light);
      expect(DolphinColors.ground, const Color(0xFF000000));
      applyThemeOverrides(null);
    });

    test('«پذیرفتن» aqua is darkened only as far as white needs, in both looks', () {
      for (final b in [Brightness.light, Brightness.dark]) {
        DolphinCustomerTheme.apply(b == Brightness.dark ? DolphinThemeChoice.dark : DolphinThemeChoice.light,
            platform: Brightness.light);
        expect(contrast(DolphinColors.onFill, DolphinColors.accentFill), greaterThanOrEqualTo(4.5));
      }
      expect(readableFill(const Color(0xFF1462E0), Colors.white), const Color(0xFF1462E0)); // already reads
    });
  });

  group('window sizes', () {
    test('C1 380 × 580; a small screen gets less, never under 360 × 540', () {
      expect(homeWindowSize(const Size(1920, 1040)), kDolphinHomeWindowSize);
      expect(homeWindowSize(const Size(1093, 614)), const Size(380, 554)); // 1366 × 768 at 125 %
      expect(homeWindowSize(const Size(300, 400)), kDolphinHomeMinSize);
    });
  });

  group('C1 main window', () {
    testWidgets('the approved order: status, ID, tiles, network, share; ⚙ opens settings', (tester) async {
      var settings = 0;
      await _at(tester, kDolphinHomeWindowSize, _main(onSettings: () => settings++));
      addTearDown(tester.view.reset);
      double top(Finder f) => tester.getTopLeft(f).dy;
      final order = [
        find.byKey(const ValueKey('dolphin-status-card')),
        find.byKey(const ValueKey('dolphin-id-card')),
        find.byKey(const ValueKey('dolphin-tile-health')),
        find.byKey(const ValueKey('dolphin-net-status-icon')),
        find.byKey(const ValueKey('dolphin-share')),
        find.byKey(const ValueKey('dolphin-home-footer')),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(top(order[i]), greaterThan(top(order[i - 1])), reason: 'item $i');
      }
      // All of it fits the 380 × 580 window without scrolling.
      expect(tester.getBottomLeft(order.last).dy, lessThanOrEqualTo(580));
      expect(find.text('۰۲۱-۴۴۲۸۰۵۰۵'), findsOneWidget);
      expect(find.text('نسخه‌ی ۲.۲.۰'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dolphin-settings')));
      expect(settings, 1);
      // The three tiles share the width.
      final w = tester.getSize(find.byKey(const ValueKey('dolphin-tile-report'))).width;
      expect(w, closeTo(tester.getSize(find.byKey(const ValueKey('dolphin-tile-screenshot'))).width, 1));
    });
  });

  group('light and dark: every new view reads and fits its window', () {
    for (final dark in [false, true]) {
      final tag = dark ? 'dark' : 'light';
      testWidgets('C1 main ($tag)', (tester) async {
        addTearDown(tester.view.reset);
        for (final view in [
          _main(),
          _main(connected: 1),
          _main(state: DolphinServerState.offline),
          _main(state: DolphinServerState.stopped),
        ]) {
          await _at(tester, kDolphinHomeWindowSize, view, dark: dark);
          expect(tester.takeException(), isNull);
          expectAllTextReadable(tester);
        }
      });

      testWidgets('C2 accept and C3 session ($tag)', (tester) async {
        addTearDown(tester.view.reset);
        await _at(tester, const Size(320, 520),
            DolphinAcceptView(verdict: _ali, peerName: 'x', onAccept: (_) {}, onDeny: () {}, showElevate: true,
                onAcceptElevate: (_) {}),
            dark: dark);
        expect(tester.takeException(), isNull);
        expectAllTextReadable(tester);
        for (final v in [TechCheck.checking, TechCheck.unverifiable, TechCheck.rejected]) {
          await _at(tester, const Size(320, 520),
              DolphinAcceptView(verdict: TechVerdict(v), peerName: 'x', phone: '021-44280505', onAccept: (_) {}, onDeny: () {}),
              dark: dark);
          expectAllTextReadable(tester);
        }
        await _at(tester, const Size(300, 380),
            DolphinSessionView(
                technician: 'علی رضایی', elapsed: const Duration(minutes: 3), keyboard: true, clipboard: false, file: true,
                soundOffered: true, paused: true, inputOff: 'علی رضایی خاموش کرد، همین حالا', onPause: (_) {},
                onToggle: (_, __) {}, onEnd: () {}, onFrame: (_) {}, onChat: () {}),
            dark: dark);
        expect(tester.takeException(), isNull);
        expectAllTextReadable(tester);
        await _at(tester, const Size(300, 380), DolphinEndedView(reason: DolphinEndReason.technician, onClose: () {}),
            dark: dark);
        expectAllTextReadable(tester);
      });

      testWidgets('«ارائه دمو», the customer side ($tag)', (tester) async {
        addTearDown(tester.view.reset);
        for (final canSee in [true, false]) {
          await _at(tester, const Size(320, 520),
              DolphinDemoAskView(
                  technician: 'علی رضایی', canSee: canSee, secondsLeft: 42, phone: '021-44280505', onSee: () {}, onNo: () {}),
              dark: dark);
          expect(tester.takeException(), isNull);
          expectAllTextReadable(tester);
        }
        expect(contrast(DolphinColors.onFill, DolphinColors.accentFill), greaterThanOrEqualTo(4.5)); // «دیدن»
        await _at(tester, const Size(900, 60),
            DolphinDemoWindowBar(title: demoWindowTitle('علی رضایی'), screens: 2, onScreen: (_) {}, onEnd: () {}),
            dark: dark);
        expect(tester.takeException(), isNull);
        expectAllTextReadable(tester);
        for (final was in [true, false]) {
          await _at(tester, const Size(380, 300),
              DolphinLight(child: Center(child: DolphinDemoEndedView(wasConnected: was, onClose: () {}))),
              dark: dark);
          expectAllTextReadable(tester);
        }
      });

      testWidgets('C5 settings and C6 first run ($tag)', (tester) async {
        addTearDown(tester.view.reset);
        await _at(tester, const Size(360, 520), _settings(), dark: dark);
        expect(tester.takeException(), isNull);
        expectAllTextReadable(tester);
        await _at(tester, const Size(360, 520), _settings(locked: true), dark: dark);
        expectAllTextReadable(tester);
        for (final step in [0, 1, 2]) {
          await _at(tester, kDolphinHomeWindowSize,
              DolphinFirstRunView(id: '123456789', onCopy: () {}, onNext: () {}, initialStep: step),
              dark: dark);
          expect(tester.takeException(), isNull);
          expectAllTextReadable(tester);
        }
      });
    }
  });
}
