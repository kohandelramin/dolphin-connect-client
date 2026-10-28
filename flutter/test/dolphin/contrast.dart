import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// A dark Windows: the platform says dark and the app theme mode follows it, as upstream's default "system" does.
Widget darkApp(Widget child) => MediaQuery(
      data: const MediaQueryData(platformBrightness: Brightness.dark),
      child: MaterialApp(
        theme: dolphinTheme(ThemeData.light()),
        darkTheme: dolphinTheme(ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF18191E))),
        themeMode: ThemeMode.dark,
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
      ),
    );

/// The colour painted behind [finder]: the nearest opaque Material or decorated box, with translucent layers blended.
Color backgroundOf(WidgetTester tester, Finder finder) {
  final layers = <Color>[];
  tester.element(finder).visitAncestorElements((e) {
    final w = e.widget;
    Color? c;
    if (w is Material) c = w.color;
    if (w is DecoratedBox && w.decoration is BoxDecoration) c = (w.decoration as BoxDecoration).color;
    if (c != null && c.alpha != 0) {
      layers.add(c);
      if (c.alpha == 255) return false;
    }
    return true;
  });
  var out = layers.isEmpty ? Colors.white : layers.last;
  for (final c in layers.reversed.skip(1)) {
    out = Color.alphaBlend(c, out);
  }
  return out;
}

TextStyle _styleOf(WidgetTester tester, Finder text) =>
    tester.widget<RichText>(find.descendant(of: text, matching: find.byType(RichText)).first).text.style!;

/// The effective text colour of a Text, over its background.
Color textColorOf(WidgetTester tester, Finder text) =>
    Color.alphaBlend(_styleOf(tester, text).color!, backgroundOf(tester, text));

double textContrast(WidgetTester tester, Finder text) =>
    contrast(textColorOf(tester, text), backgroundOf(tester, text));

/// Every Text on screen reaches AA (4.5:1; 3:1 for large text) on the colour behind it.
void expectAllTextReadable(WidgetTester tester) {
  final texts = find.byType(Text).evaluate().toList();
  for (var i = 0; i < texts.length; i++) {
    final f = find.byWidget(texts[i].widget).first;
    final t = texts[i].widget as Text;
    final style = _styleOf(tester, f);
    final size = style.fontSize ?? 14;
    final large = size >= 24 || (size >= 18.66 && (style.fontWeight?.index ?? 3) >= FontWeight.w700.index);
    expect(textContrast(tester, f), greaterThanOrEqualTo(large ? 3.0 : 4.5),
        reason: 'text "${t.data ?? t.textSpan}" is unreadable on a dark Windows');
  }
}
