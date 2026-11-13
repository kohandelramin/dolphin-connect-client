import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/receive_folder.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  test('the folder shows only when the app gives a path (DD-12)', () {
    expect(receiveFolderShown(r'C:\Users\Ali\Downloads\دریافتی دلفین'), isTrue);
    expect(receiveFolderShown(''), isFalse); // the portal's switch hides it: upstream behaviour
    expect(receiveFolderShown('  '), isFalse);
  });

  testWidgets('the strip names the folder and shows its path', (tester) async {
    const path = r'C:\Users\Ali\Downloads\دریافتی دلفین';
    await tester.pumpWidget(_app(const DolphinReceiveFolderView(path: path)));
    expect(find.text(kReceiveFolderLabel), findsOneWidget);
    expect(find.text(path), findsOneWidget);
    expect(path, endsWith(kReceiveFolderName)); // the same name as src/dolphin_system_core.rs RECEIVE_FOLDER_NAME

    await tester.pumpWidget(_app(const DolphinReceiveFolderView(path: '')));
    expect(find.byKey(const ValueKey('dolphin-receive-folder')), findsNothing);
  });
}
