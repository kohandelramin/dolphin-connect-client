import 'package:flutter/material.dart';

import 'theme.dart';

/// DD-15: the technician app's panel (WebView2 of the portal) after the staff sign-in has expired mid-use (staff
/// sessions end after 8 h): «ورود منقضی شد» and one «ورود دوباره», instead of the English "Sign in as staff." a 401
/// route answers with, or a page the technician cannot place. Hook: flutter/lib/dolphin/portal_view.dart.
///
/// Two signs, both from the portal itself:
/// - the sign-in page with `expired=1`, where the portal sends an action whose session has ended
///   (app/src/lib/auth/web.ts `requireStaffInAction`);
/// - a top-level 401, the answer of the portal's routes (CSV export, reports) to a signed-out request, read from the
///   page's own `PerformanceNavigationTiming.responseStatus` (webview_windows gives no HTTP status).
/// A plain `/staff/login` is not counted: the portal sends there after «خروج» too, and that page is already Persian.

const kSignInExpiredTitle = 'ورود منقضی شد';
const kSignInExpiredText = 'زمان ورود شما به پنل دلفین تمام شده است. دوباره وارد شوید؛ اگر چیزی نوشته بودید، دوباره بنویسید.';
const kSignInAgainLabel = 'ورود دوباره';

/// Read in the page after each navigation: the HTTP status of the top-level document, 0 when the browser does not say.
const kNavigationStatusScript =
    "(function(){try{var n=performance.getEntriesByType('navigation')[0];return n&&n.responseStatus?n.responseStatus:0;}catch(e){return 0;}})()";

const _login = '/staff/login';

String _rest(String url, String portalUrl) => url.startsWith(portalUrl) ? url.substring(portalUrl.length) : '';

/// The panel's own pages (under `/staff/`), not the sign-in page.
bool isStaffPanelPage(String url, String portalUrl) {
  final rest = _rest(url, portalUrl);
  if (!rest.startsWith('/staff/') && rest != '/staff' && !rest.startsWith('/staff?')) return false;
  return !isStaffLoginPage(url, portalUrl);
}

/// The staff sign-in page, with or without a query.
bool isStaffLoginPage(String url, String portalUrl) {
  final rest = _rest(url, portalUrl);
  return rest == _login || rest.startsWith('$_login?') || rest.startsWith('$_login#') || rest.startsWith('$_login/');
}

/// Whether [url] (already known to be a portal page) says the sign-in expired. [status] is the document's HTTP status
/// from [kNavigationStatusScript], 0 when not known.
bool signInExpiredAt(String url, String portalUrl, {int status = 0}) {
  if (!url.startsWith(portalUrl)) return false;
  if (status == 401) return true;
  if (!isStaffLoginPage(url, portalUrl)) return false;
  final query = Uri.tryParse(url)?.queryParameters ?? const {};
  return query['expired'] == '1';
}

/// Where «ورود دوباره» goes: the sign-in page, back to [lastPage] afterwards when it was a panel page (the portal checks
/// `next` again, app/src/lib/next-path.ts).
String signInAgainUrl(String portalUrl, String? lastPage) {
  final page = lastPage;
  if (page == null || !isStaffPanelPage(page, portalUrl)) return '$portalUrl$_login';
  return '$portalUrl$_login?next=${Uri.encodeComponent(_rest(page, portalUrl))}';
}

/// The notice over the panel: one message, one button.
class DolphinSignInExpired extends StatelessWidget {
  final VoidCallback onSignIn;
  const DolphinSignInExpired({super.key, required this.onSignIn});

  @override
  Widget build(BuildContext context) => DolphinLight(child: Builder(builder: _build));

  Widget _build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: ColoredBox(
          key: const ValueKey('dolphin-signin-expired'),
          color: DolphinColors.ground,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock_clock_outlined, size: 44, color: DolphinColors.azureText),
                  const SizedBox(height: 12),
                  Text(kSignInExpiredTitle,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
                  const SizedBox(height: 8),
                  Text(kSignInExpiredText,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, height: 1.8, color: DolphinColors.muted)),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: onSignIn, child: const Text(kSignInAgainLabel)),
                ]),
              ),
            ),
          ),
        ),
      );
}
