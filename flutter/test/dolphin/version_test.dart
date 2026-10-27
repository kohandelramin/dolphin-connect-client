import 'package:flutter_hbb/dolphin/digits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('versions read in Persian digits, our number and never the engine number', () {
    expect(faDigits('2.0.1'), '۲.۰.۱');
    expect(versionLabel('2.0.0'), 'نسخه‌ی ۲.۰.۰');
    expect(versionLabel('2.0.0-rc.1'), 'نسخه‌ی ۲.۰.۰-rc.۱');
  });
}
