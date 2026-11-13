import 'package:flutter_hbb/dolphin/switches.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the pushed switches and keeps the defaults for anything missing or bad (DD-4)', () {
    final s = DolphinSwitches.parse('{"share-toggle":"forced","remote-printer":"available","stay-in-tray":"loud",'
        '"new-thing":"forced"}');
    expect(s.mode(DolphinSwitch.shareToggle), SwitchMode.forced);
    expect(s.mode(DolphinSwitch.remotePrinter), SwitchMode.available);
    expect(s.mode(DolphinSwitch.stayInTray), SwitchMode.available); // bad value: default
    expect(s.mode(DolphinSwitch.safeMode), SwitchMode.hidden); // missing: default
    for (final raw in ['-', '', 'not json', '[1,2]']) {
      expect(DolphinSwitches.parse(raw).mode(DolphinSwitch.directRoute), SwitchMode.forced, reason: raw);
    }
    expect(DolphinSwitches.parse('{}').mode('never-heard-of'), SwitchMode.hidden);
  });

  test('a choice counts only when the switch is available', () {
    final s = DolphinSwitches.parse('{"share-toggle":"available","stay-in-tray":"forced","receive-folder":"hidden"}');
    expect(s.on(DolphinSwitch.shareToggle, chosen: false), isFalse);
    expect(s.on(DolphinSwitch.shareToggle), isTrue);
    expect(s.on(DolphinSwitch.shareToggle, defaultOn: false), isFalse);
    expect(s.on(DolphinSwitch.stayInTray, chosen: false), isTrue);
    expect(s.on(DolphinSwitch.receiveFolder, chosen: true), isFalse);
    expect(s.shown(DolphinSwitch.receiveFolder), isFalse);
  });
}
