import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/signin_expired.dart';
import 'package:flutter_test/flutter_test.dart';

const _p = 'https://support.dolphindev.ir';

void main() {
  test('the sign-in page and the panel pages are told apart (DD-15)', () {
    expect(isStaffLoginPage('$_p/staff/login', _p), isTrue);
    expect(isStaffLoginPage('$_p/staff/login?expired=1&next=%2Fstaff%2Fcomputers', _p), isTrue);
    expect(isStaffLoginPage('$_p/staff/loginx', _p), isFalse);
    expect(isStaffLoginPage('https://evil.example/staff/login', _p), isFalse);
    expect(isStaffPanelPage('$_p/staff/computers', _p), isTrue);
    expect(isStaffPanelPage('$_p/staff/side/123456789', _p), isTrue);
    expect(isStaffPanelPage('$_p/staff', _p), isTrue);
    expect(isStaffPanelPage('$_p/staff/login', _p), isFalse);
    expect(isStaffPanelPage('$_p/portal', _p), isFalse);
  });

  test('expired: the portal\'s expired=1 sign-in page, or a 401; not a plain sign-in or «خروج»', () {
    expect(signInExpiredAt('$_p/staff/login?expired=1&next=%2Fstaff%2Frequests', _p), isTrue);
    expect(signInExpiredAt('$_p/staff/login', _p), isFalse); // first sign-in and «خروج» land here too
    expect(signInExpiredAt('$_p/staff/login?next=%2Fstaff', _p), isFalse);
    expect(signInExpiredAt('$_p/staff/organizations/4/export', _p, status: 401), isTrue); // "Sign in as staff."
    expect(signInExpiredAt('$_p/staff/computers', _p, status: 200), isFalse);
    expect(signInExpiredAt('$_p/staff/computers', _p), isFalse);
    expect(signInExpiredAt('https://evil.example/staff/login?expired=1', _p), isFalse);
  });

  test('«ورود دوباره» goes to the sign-in page and back to the last panel page', () {
    expect(signInAgainUrl(_p, '$_p/staff/computers?tag=3'), '$_p/staff/login?next=%2Fstaff%2Fcomputers%3Ftag%3D3');
    expect(signInAgainUrl(_p, null), '$_p/staff/login');
    expect(signInAgainUrl(_p, '$_p/staff/login'), '$_p/staff/login');
    expect(signInAgainUrl(_p, 'https://evil.example/staff/x'), '$_p/staff/login');
  });

  test('the status script only reads the page', () {
    expect(kNavigationStatusScript, contains("getEntriesByType('navigation')"));
    expect(kNavigationStatusScript, contains('responseStatus'));
    expect(kNavigationStatusScript, isNot(contains('=>'))); // plain ES5 for any WebView2
  });

  testWidgets('one message, one button', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DolphinSignInExpired(onSignIn: () => pressed++))));
    expect(find.text(kSignInExpiredTitle), findsOneWidget);
    expect(find.text(kSignInExpiredText), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.text(kSignInAgainLabel));
    expect(pressed, 1);
  });
}
