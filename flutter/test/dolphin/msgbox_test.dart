import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

void main() {
  test('message box success and error colours carry white text at AA (D20)', () {
    // Upstream #32bea6 is 2.3:1 and #E04F5F 3.9:1 with white.
    expect(contrast(Colors.white, DolphinColors.msgSuccess), greaterThanOrEqualTo(4.5));
    expect(contrast(Colors.white, DolphinColors.msgError), greaterThanOrEqualTo(4.5));
  });

  test('common.dart takes both colours from DolphinColors', () {
    final src = File('lib/common.dart').readAsStringSync();
    final fn = src.split('Color? _msgboxColor(String type)')[1].split('Widget msgboxIcon')[0];
    expect(fn, contains('DolphinColors.msgSuccess'));
    expect(fn, contains('DolphinColors.msgError'));
    expect(fn, isNot(contains('32bea6')));
    expect(fn, isNot(contains('E04F5F')));
  });
}
