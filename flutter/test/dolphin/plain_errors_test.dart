import 'package:flutter_hbb/dolphin/plain_errors.dart';
import 'package:flutter_test/flutter_test.dart';

final _persian = RegExp(r'[؀-ۿ]');
final _latinStart = RegExp(r'^(?:[A-Za-z]|\.\.\.)');

void main() {
  test('each Windows error code the table knows has a Persian text with what to do (DD-13)', () {
    expect(dolphinPlainErrorCodes, isNotEmpty);
    expect(dolphinPlainErrorCodes.toSet().length, dolphinPlainErrorCodes.length, reason: 'a code in two rows');
    for (final code in dolphinPlainErrorCodes) {
      final t = dolphinPlainError('Something. (os error $code)');
      expect(t, isNotNull, reason: '$code');
      expect(_persian.hasMatch(t!), isTrue, reason: '$code');
      // Written for a bidi-aware renderer: never starts with a Latin word (the reversed-text trap, UX-12).
      expect(_latinStart.hasMatch(t), isFalse, reason: '$code');
      expect(t, contains('؛'), reason: '$code: what happened; what to do');
      expect(t, endsWith('(کد $code)'), reason: 'the code stays for support');
    }
  });

  test('the errors a customer or technician hits read plainly', () {
    expect(dolphinPlainError('Access is denied. (os error 5)'), startsWith('اجازه‌ی دسترسی'));
    expect(dolphinPlainError(
            'The process cannot access the file because it is being used by another process. (os error 32)'),
        contains('باز است'));
    expect(dolphinPlainError('There is not enough space on the disk. (os error 112)'), contains('دیسک'));
    expect(dolphinPlainError('Failed to connect via relay server: An existing connection was forcibly closed by the '
            'remote host. (os error 10054)'),
        contains('قطع شد'));
    expect(dolphinPlainError('A connection attempt failed … (os error 10060)'), contains('پاسخی نیامد'));
    // The same error in the PC's own language still matches by its code.
    expect(dolphinPlainError('دسترسی مجاز نیست. (os error 5)'), startsWith('اجازه‌ی دسترسی'));
    // Without a code, upstream's English wording.
    expect(dolphinPlainError('Permission denied'), isNotNull);
    expect(dolphinPlainError('deadline has elapsed: timed out'), contains('پاسخی نیامد'));
  });

  test('anything else is left to upstream and the fa.rs overlay', () {
    for (final t in ['Wrong Password', 'Remote desktop is offline', 'dolphin_share_stopped', 'Timeout', '',
        'Something. (os error 99999)']) {
      expect(dolphinPlainError(t), isNull, reason: t);
    }
  });
}
