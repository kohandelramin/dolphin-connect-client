import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/session_toolbar.dart';
import 'package:flutter_hbb/dolphin/sound.dart';
import 'package:flutter_hbb/dolphin/switches.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// DD-31: «صدای رایانه‌ی مشتری» on the technician's toolbar, off at the start of every session.
void main() {
  test('the state: the organization first, then the customer\'s own switch, then the toggle', () {
    expect(soundState(peerOffers: true, audioPermission: true, muted: true), DolphinSound.off);
    expect(soundState(peerOffers: true, audioPermission: true, muted: false), DolphinSound.on);
    // an older customer app says nothing: it sends sound as upstream does, so the button works
    expect(soundState(peerOffers: null, audioPermission: null, muted: true), DolphinSound.off);
    expect(soundState(peerOffers: null, audioPermission: null, muted: false), DolphinSound.on);
    expect(soundState(peerOffers: false, audioPermission: true, muted: false), DolphinSound.notOffered);
    expect(soundState(peerOffers: false, audioPermission: false, muted: true), DolphinSound.notOffered);
    expect(soundState(peerOffers: true, audioPermission: false, muted: false), DolphinSound.closedByCustomer);
    expect(soundCanToggle(DolphinSound.on), isTrue);
    expect(soundCanToggle(DolphinSound.off), isTrue);
    expect(soundCanToggle(DolphinSound.notOffered), isFalse);
    expect(soundCanToggle(DolphinSound.closedByCustomer), isFalse);
    expect(soundReason(DolphinSound.on), isNull);
    expect(soundReason(DolphinSound.notOffered), DolphinSoundText.notOffered);
    expect(soundReason(DolphinSound.closedByCustomer), DolphinSoundText.closedByCustomer);
  });

  test('the keys match the Rust side and the portal\'s default', () {
    expect(kDolphinSoundOffered, 'dolphin_sound_offered'); // src/dolphin_system_core.rs PLATFORM_SOUND_OFFERED
    expect(kDolphinSoundToggle, 'disable-audio'); // upstream's session toggle (src/client.rs)
    expect(kSwitchDefaults[DolphinSwitch.remoteSound], SwitchMode.available);
    expect(DolphinSwitches.parse('{"remote-sound":"hidden"}').shown(DolphinSwitch.remoteSound), isFalse);
  });

  Future<void> pumpBar(WidgetTester tester, Widget bar, {Widget Function(Widget) app = lightApp}) async {
    tester.view.physicalSize = const Size(2400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(Center(child: bar)));
  }

  DolphinBarButton button(WidgetTester tester) =>
      tester.widget<DolphinBarButton>(find.byKey(const ValueKey('dolphin-bar-sound')));

  testWidgets('off and on: one button that toggles, its state in the tooltip', (tester) async {
    var pressed = 0;
    for (final (s, tip, icon) in [
      (DolphinSound.off, '${DolphinSoundText.button}: خاموش', Icons.volume_off_outlined),
      (DolphinSound.on, '${DolphinSoundText.button}: روشن', Icons.volume_up_outlined),
    ]) {
      await pumpBar(tester, DolphinSessionBar(state: const DolphinBarState(), sound: s, onSound: () => pressed++));
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      expect(find.byIcon(icon), findsOneWidget);
      await tester.tap(find.byTooltip(tip));
    }
    expect(pressed, 2);
  });

  testWidgets('not offered or closed by the customer: dimmed, with the reason and no «روشن/خاموش»', (tester) async {
    var pressed = 0;
    for (final s in [DolphinSound.notOffered, DolphinSound.closedByCustomer]) {
      await pumpBar(tester, DolphinSessionBar(state: const DolphinBarState(), sound: s, onSound: () => pressed++));
      expect(find.byTooltip(soundReason(s)!), findsOneWidget);
      expect(button(tester).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('dolphin-bar-sound')), warnIfMissed: false);
    }
    expect(pressed, 0);
  });

  testWidgets('no state, no button (other session kinds)', (tester) async {
    await pumpBar(tester, const DolphinSessionBar(state: DolphinBarState()));
    expect(find.byKey(const ValueKey('dolphin-bar-sound')), findsNothing);
  });

  for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
    testWidgets('the sound button in the $name theme reaches AA', (tester) async {
      for (final s in DolphinSound.values) {
        await pumpBar(tester, DolphinSessionBar(state: const DolphinBarState(), sound: s, onSound: () {}), app: app);
        await tester.pumpAndSettle();
        expectAllTextReadable(tester);
      }
    });
  }
}
