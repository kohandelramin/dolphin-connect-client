import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/window_sizes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the request window fits a small laptop and keeps its size on a big screen (UX-18)', () {
    expect(requestsSize(const Size(1366, 768)), const Size(980, 678));
    expect(requestsSize(const Size(1920, 1080)), kDolphinRequestsSize);
    expect(requestsSize(const Size(800, 500)), const Size(760, 480)); // never smaller than the portal can use
  });

  test('the request button says who it is for (UX-8)', () {
    expect(kRequestsWhoFor, contains('نام کاربری'));
    expect(kRequestsWhoFor, contains('پشتیبانی'));
  });
}
