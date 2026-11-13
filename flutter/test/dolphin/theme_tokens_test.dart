import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/tech_theme.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_hbb/dolphin/theme_option.dart';
import 'package:flutter_hbb/dolphin/theme_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// Plan 19: one token set for both apps; the portal's `dolphin-theme` overrides it, validated as a whole.
void main() {
  tearDown(() => applyThemeOverrides(null));

  group('built-in tokens', () {
    test('are today\'s look, light and dark', () {
      // The colours every Dolphin view used before Plan 19 (theme.dart and tech_theme.dart constants).
      expect(DolphinColors.azure, const Color(0xFF1462E0));
      expect(DolphinColors.azureText, const Color(0xFF1462E0));
      expect(DolphinColors.azureSoft, const Color(0xFFEEF5FF));
      expect(DolphinColors.azureTint, const Color(0xFFD9E8FF));
      expect(DolphinColors.aqua, const Color(0xFF0D9488));
      expect(DolphinColors.aquaText, const Color(0xFF0F766E));
      expect(DolphinColors.aquaSoft, const Color(0xFFE6F6F4));
      expect(DolphinColors.ink, const Color(0xFF0B1829));
      expect(DolphinColors.msgSuccess, const Color(0xFF0F766E));
      expect(DolphinColors.msgError, const Color(0xFFD03C4E));
      expect(DolphinColors.danger, const Color(0xFFE11D48));
      expect(DolphinColors.dangerText, const Color(0xFFBE123C));
      expect(DolphinColors.dangerSoft, const Color(0xFFFFF0F3));
      expect(DolphinColors.amberText, const Color(0xFF92400E));
      expect(DolphinColors.amberSoft, const Color(0xFFFEF6E0));
      expect(DolphinColors.fieldEdge, const Color(0xFF728AA6));
      expect(DolphinColors.ground, const Color(0xFFF6F9FF));
      expect(DolphinColors.muted, const Color(0xFF52637A));
      expect(DolphinColors.line, const Color(0xFFE2E9F3));
      expect(DolphinColors.lineStrong, const Color(0xFFC8D6E8));
      expect([DolphinRadii.field, DolphinRadii.control, DolphinRadii.card], [10, 12, 18]);
      final dark = DolphinTechPalette.dark;
      expect([dark.ground, dark.surface, dark.ink, dark.muted, dark.line, dark.lineStrong], const [
        Color(0xFF0B1829), Color(0xFF13233A), Color(0xFFE8EEF7), Color(0xFFA3B3C7), Color(0xFF22344D), Color(0xFF4A6080)
      ]);
      expect([dark.accent, dark.accentSoft, dark.okText, dark.warnText, dark.dangerText], const [
        Color(0xFF8AB8FF), Color(0xFF1B355C), Color(0xFF5EEAD4), Color(0xFFFCD34D), Color(0xFFFF9FB2)
      ]);
      expect([dark.fill, dark.radiusSmall, dark.radiusTiny], [const Color(0xFF1462E0), 8, 6]);
      expect(DolphinThemeTokens.builtInLight.fontScale, 1);
    });

    test('every text pair of the built-in tokens reaches AA', () {
      expect(contrastProblems(DolphinThemeTokens.builtInLight), isEmpty);
      expect(contrastProblems(DolphinThemeTokens.builtInDark), isEmpty);
    });

    test('the token names are the contract\'s, exactly', () {
      expect(kDolphinColorTokens, [
        'primary', 'primaryText', 'accent', 'background', 'surface', 'surfaceAlt', 'line', 'text', 'textMuted',
        'success', 'warning', 'danger'
      ]);
      expect(kDolphinNumberTokens, ['radius', 'radiusLarge', 'fontScale']);
      expect(kDolphinThemeOption, 'dolphin-theme');
    });
  });

  group('parsing', () {
    String theme(Map<String, Object?> light, [Map<String, Object?>? dark]) =>
        jsonEncode({'v': 1, 'light': light, if (dark != null) 'dark': dark});

    test('a valid override changes only its tokens; the rest stays built in', () {
      final set = parseThemeOverrides(theme({'primary': '#0A4FB8', 'radius': 8}, {'background': '#000000'}))!;
      expect(set.light.primary, const Color(0xFF0A4FB8));
      expect(set.light.radius, 8);
      expect(set.light.radiusField, 6);
      expect(set.light.text, DolphinThemeTokens.builtInLight.text);
      expect(set.light.radiusLarge, 18);
      expect(set.dark.background, const Color(0xFF000000));
      expect(set.dark.surface, DolphinThemeTokens.builtInDark.surface);
    });

    test('hex colours in either case; a missing side keeps the built-in tokens', () {
      final set = parseThemeOverrides(jsonEncode({
        'v': 1,
        'light': {'primaryText': '#0a4fb8'}
      }))!;
      expect(set.light.primaryText, const Color(0xFF0A4FB8));
      expect(set.dark, DolphinThemeTokens.builtInDark);
      expect(parseThemeOverrides('{"v":1}'), DolphinThemeSet.builtIn);
    });

    test('unknown keys are ignored, at the top and inside a side', () {
      final set = parseThemeOverrides(jsonEncode({
        'v': 1,
        'name': 'نوروز',
        'light': {'primary': '#0A4FB8', 'shadow': 'big', 'spacing': 99}
      }))!;
      expect(set.light.primary, const Color(0xFF0A4FB8));
    });

    test('anything malformed ignores the whole value', () {
      for (final raw in [
        '',
        '-',
        'not json',
        '[]',
        '"x"',
        '{"light":{"primary":"#0A4FB8"}}', // no version
        '{"v":2,"light":{"primary":"#0A4FB8"}}', // a version this app does not know
        '{"v":"1"}',
        '{"v":1,"light":"blue"}',
        '{"v":1,"light":{"primary":"#0A4FB8"},"dark":[]}',
        '{"v":1,"light":{"primary":"blue"}}',
        '{"v":1,"light":{"primary":"#0A4FB"}}',
        '{"v":1,"light":{"primary":"#0A4FB8FF"}}',
        '{"v":1,"light":{"primary":"0A4FB8"}}',
        '{"v":1,"light":{"primary":12}}',
        '{"v":1,"light":{"radius":"8"}}',
        '{"v":1,"light":{"primary":"#0A4FB8","radius":null}}',
      ]) {
        expect(parseThemeOverrides(raw), isNull, reason: raw);
      }
    });

    test('numbers outside their bounds ignore the whole value; the bounds themselves are allowed', () {
      for (final (key, bad, edge) in [
        ('radius', 25, 24),
        ('radius', -1, 0),
        ('radiusLarge', 33, 32),
        ('fontScale', 1.31, 1.3),
        ('fontScale', 0.84, 0.85),
      ]) {
        expect(parseThemeOverrides(theme({key: bad})), isNull, reason: '$key $bad');
        expect(parseThemeOverrides(theme({key: edge}))!.light.number(key), edge, reason: '$key $edge');
      }
    });

    test('an override whose text would not read (below AA) is refused as a whole', () {
      // light grey text on the white surface: 1.5:1
      expect(parseThemeOverrides(theme({'text': '#CCCCCC'})), isNull);
      // a pale primary: white labels on it would not read
      expect(parseThemeOverrides(theme({'primary': '#9EC2FF'})), isNull);
      // dark text on the dark ground
      expect(parseThemeOverrides(theme({}, {'text': '#1A1A1A'})), isNull);
      // a problem in dark refuses the light part too
      expect(parseThemeOverrides(theme({'primary': '#0A4FB8'}, {'textMuted': '#334455'})), isNull);
      final problems = contrastProblems(DolphinThemeTokens.builtInLight.merged({'text': const Color(0xFFCCCCCC)}, {}));
      expect(problems, containsAll(['text on background', 'text on surface']));
    });

    test('derived colours follow the tokens they come from, and only those', () {
      final t = DolphinThemeTokens.builtInLight.merged({'danger': const Color(0xFF9F1239)}, {});
      expect(t.dangerFill, const Color(0xFF9F1239));
      expect(t.errorIcon, const Color(0xFF9F1239));
      expect(t.dangerSoft, isNot(DolphinThemeTokens.builtInLight.dangerSoft));
      expect(t.primaryTint, DolphinThemeTokens.builtInLight.primaryTint);
      expect(t.lineStrong, DolphinThemeTokens.builtInLight.lineStrong);
      // The same value as the built-in one changes nothing, derived colours included.
      expect(DolphinThemeTokens.builtInLight.merged({'primary': const Color(0xFF1462E0)}, {}),
          DolphinThemeTokens.builtInLight);
    });
  });

  group('applying', () {
    test('a valid value is put in use; empty, "-" and null go back to the built-in tokens', () {
      expect(applyThemeOverrides('{"v":1,"light":{"primary":"#0A4FB8"}}'), ThemeOverrideResult.applied);
      expect(DolphinColors.azure, const Color(0xFF0A4FB8));
      expect(applyThemeOverrides('-'), ThemeOverrideResult.builtIn);
      expect(DolphinColors.azure, const Color(0xFF1462E0));
      applyThemeOverrides('{"v":1,"light":{"primary":"#0A4FB8"}}');
      expect(applyThemeOverrides(''), ThemeOverrideResult.builtIn);
      expect(DolphinTheme.active.value, DolphinThemeSet.builtIn);
      applyThemeOverrides('{"v":1,"light":{"primary":"#0A4FB8"}}');
      expect(applyThemeOverrides(null), ThemeOverrideResult.builtIn);
      expect(DolphinTheme.active.value, DolphinThemeSet.builtIn);
    });

    test('a malformed value never leaves a half-applied look: the built-in tokens stay', () {
      applyThemeOverrides('{"v":1,"light":{"primary":"#0A4FB8"}}');
      expect(applyThemeOverrides('{"v":1,"light":{"primary":"#0A4FB8","text":"#FFFFFF"}}'), ThemeOverrideResult.ignored);
      expect(DolphinTheme.active.value, DolphinThemeSet.builtIn);
    });

    test('the technician app passes the decoded /config theme as it is', () {
      expect(
          applyThemeOverrides({
            'v': 1,
            'dark': {'surface': '#101820', 'radiusLarge': 24}
          }),
          ThemeOverrideResult.applied);
      expect(DolphinTechPalette.dark.surface, const Color(0xFF101820));
      expect(DolphinTheme.dark.radiusLarge, 24);
      expect(applyThemeOverrides({'v': 1, 'dark': 'x'}), ThemeOverrideResult.ignored);
    });

    test('listeners hear a change, not the same value again', () {
      var heard = 0;
      void listener() => heard++;
      DolphinTheme.active.addListener(listener);
      addTearDown(() => DolphinTheme.active.removeListener(listener));
      applyThemeOverrides('{"v":1,"light":{"primary":"#0A4FB8"}}');
      applyThemeOverrides('{"v":1,"light":{"primary":"#0A4FB8"}}');
      expect(heard, 1);
      applyThemeOverrides('-');
      applyThemeOverrides('');
      expect(heard, 2);
    });

    testWidgets('a themed customer view paints the override, and fontScale scales its text', (tester) async {
      applyThemeOverrides('{"v":1,"light":{"background":"#FFF8EE","radius":4,"fontScale":1.2}}');
      await tester.pumpWidget(MaterialApp(
          home: DolphinLight(
              child: Builder(
                  builder: (context) => Column(children: [
                        Text('x', style: TextStyle(color: DolphinColors.ink)),
                        FilledButton(onPressed: () {}, child: const Text('ok')),
                      ])))));
      expect(backgroundOf(tester, find.text('x')), const Color(0xFFFFF8EE));
      expect(MediaQuery.of(tester.element(find.text('x'))).textScaler.scale(10), closeTo(12, 0.001));
      final shape = Theme.of(tester.element(find.text('ok'))).filledButtonTheme.style!.shape!.resolve({})!
          as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(4));
    });

    testWidgets('a running app takes a new theme without losing its state', (tester) async {
      dolphinRebuildOnThemeChange();
      await tester.pumpWidget(const MaterialApp(home: DolphinLight(child: _Counter())));
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      applyThemeOverrides('{"v":1,"light":{"text":"#1F2937"}}');
      await tester.pump();
      expect(find.text('1'), findsOneWidget); // same state
      expect(textColorOf(tester, find.text('1')), const Color(0xFF1F2937));
    });

    testWidgets('a theme applied while the tree builds (in initState of a window) lands after that frame', (tester) async {
      dolphinRebuildOnThemeChange();
      await tester.pumpWidget(const MaterialApp(home: DolphinLight(child: _AppliesInInit())));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(textColorOf(tester, find.text('y')), const Color(0xFF1F2937));
    });

    test('the customer app parses the option only when its text changed', () {
      expect(themeValueChanged(null, ''), isTrue); // the first read always counts
      expect(themeValueChanged('', ''), isFalse);
      expect(themeValueChanged('', '{"v":1}'), isTrue);
      expect(themeValueChanged('{"v":1}', '{"v":1}'), isFalse);
      expect(kDolphinThemeAppliedLocal, 'dolphin-theme-applied');
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text('$n', style: TextStyle(color: DolphinColors.ink)),
        TextButton(onPressed: () => setState(() => n++), child: const Text('+')),
      ]);
}

class _AppliesInInit extends StatefulWidget {
  const _AppliesInInit();
  @override
  State<_AppliesInInit> createState() => _AppliesInInitState();
}

class _AppliesInInitState extends State<_AppliesInInit> {
  @override
  void initState() {
    super.initState();
    applyThemeOverrides('{"v":1,"light":{"text":"#1F2937"}}');
  }

  @override
  Widget build(BuildContext context) => Text('y', style: TextStyle(color: DolphinColors.ink));
}
