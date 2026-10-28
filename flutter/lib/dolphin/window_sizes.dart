import 'package:flutter/widgets.dart';

/// The request section's preferred window: room for the portal's pages.
const kDolphinRequestsSize = Size(980, 720);

/// The request section's window on this screen (UX-18): up to 980 × 720, never larger than the screen leaves room for.
/// A 1366 × 768 laptop has about 728 px under the taskbar, so 720 + the title bar did not fit.
Size requestsSize(Size screen) => Size(
      (screen.width - 40).clamp(640.0, kDolphinRequestsSize.width),
      (screen.height - 90).clamp(480.0, kDolphinRequestsSize.height),
    );
