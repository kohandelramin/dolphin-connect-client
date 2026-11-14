import 'package:flutter/widgets.dart';

/// Plan 19 C4: «درخواست‌ها و پیام‌ها» (native since 2.2.0) opens at 460 × 640 and can be resized, never under the home
/// window's minimum ([kDolphinHomeMinSize], which every C4 screen fits).
const kDolphinRequestsSize = Size(460, 640);

/// The request section's window on this screen (UX-18): 460 × 640, smaller only on a screen that cannot hold it.
Size requestsSize(Size screen) => Size(
      (screen.width - 20).clamp(kDolphinHomeMinSize.width, kDolphinRequestsSize.width),
      (screen.height - 60).clamp(kDolphinHomeMinSize.height, kDolphinRequestsSize.height),
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
