import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/window_sizes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the request window is 460 × 640 (C4), smaller only on a small screen, never under the home minimum', () {
    expect(kDolphinRequestsSize, const Size(460, 640));
    expect(requestsSize(const Size(1366, 768)), const Size(460, 640));
    expect(requestsSize(const Size(1920, 1080)), kDolphinRequestsSize);
    expect(requestsSize(const Size(1093, 614)), const Size(460, 554)); // a 1366 × 768 laptop at 125 %
    expect(requestsSize(const Size(300, 400)), kDolphinHomeMinSize);
  });

  test('the request button says who it is for (UX-8)', () {
    expect(kRequestsWhoFor, contains('نام کاربری'));
    expect(kRequestsWhoFor, contains('پشتیبانی'));
  });
}
