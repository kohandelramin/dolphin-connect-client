import 'package:flutter/widgets.dart';

/// The request section's preferred window: room for the portal's pages.
const kDolphinRequestsSize = Size(980, 720);

/// The request section's window on this screen (UX-18): up to 980 × 720, never larger than the screen leaves room for.
/// A 1366 × 768 laptop has about 728 px under the taskbar, so 720 + the title bar did not fit.
Size requestsSize(Size screen) => Size(
      (screen.width - 40).clamp(640.0, kDolphinRequestsSize.width),
      (screen.height - 90).clamp(480.0, kDolphinRequestsSize.height),
    );

/// Plan 19 C1: the customer window is 380 × 580, as approved. A screen that cannot hold that (a 1366 × 768 laptop at
/// 125 % has about 614 logical pixels under the taskbar's edge) gets a smaller one, never under 360 × 540; the content
/// scrolls and the footer stays.
const kDolphinHomeWindowSize = Size(380, 580);
const kDolphinHomeMinSize = Size(360, 540);

Size homeWindowSize(Size screen) => Size(
      (screen.width - 20).clamp(kDolphinHomeMinSize.width, kDolphinHomeWindowSize.width),
      (screen.height - 60).clamp(kDolphinHomeMinSize.height, kDolphinHomeWindowSize.height),
    );
