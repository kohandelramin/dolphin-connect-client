import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/call_status.dart';
import 'package:flutter_hbb/dolphin/technician_header.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// AUI-2: the technician's own ID was white on a white header on a dark Windows.
void main() {
  testWidgets('the technician header on a dark Windows: ID and field text are dark on white', (tester) async {
    tester.view.physicalSize = const Size(2400, 600); // test font glyphs are wide
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final manual = TextEditingController(text: '123 456 789');
    final call = DolphinCallWait(const Duration(seconds: 8));
    await tester.pumpWidget(
        darkApp(DolphinTechnicianHeader(myId: '287654321', manual: manual, call: call, onConnect: () {})));
    // SelectableText draws through an EditableText, which find.text does not match.
    final id = find.descendant(of: find.byType(SelectableText), matching: find.byType(EditableText));
    expect(id, findsOneWidget);
    final idText = tester.widget<EditableText>(id);
    expect(idText.controller.text, '287 654 321');
    expect(idText.style.color, DolphinColors.ink);
    expect(backgroundOf(tester, id), Colors.white);
    expect(contrast(idText.style.color!, backgroundOf(tester, id)), greaterThanOrEqualTo(4.5));
    expectAllTextReadable(tester);
    final field = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(contrast(field.style.color!, Colors.white), greaterThanOrEqualTo(4.5));
    call.dispose();
    manual.dispose();
  });
}
