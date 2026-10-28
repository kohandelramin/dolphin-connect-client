import 'dart:convert';

/// Messages between a Dolphin Connect app and the portal page inside it (design 2026-10-27, section 4; Plan 13):
/// the technician app with the staff panel, the customer app with the customer portal.
/// Pure, so it is unit-tested without the app's native parts.

/// A message from the portal page (app/src/lib/app-bridge.ts). Anything else is ignored.
class PanelMessage {
  final String type;
  final String id;

  /// The customer's one-time code, on `dolphin-connect` for a code-mode PC (WF-3). Empty otherwise.
  final String code;

  /// `dolphin-call-result` only: whether the panel opened the call, and what to tell the technician.
  final bool ok;
  final String text;

  const PanelMessage(this.type, [this.id = '', this.code = ''])
      : ok = false,
        text = '';
  const PanelMessage.callResult(this.ok, this.text)
      : type = 'dolphin-call-result',
        id = '',
        code = '';
}

final panelIdPattern = RegExp(r'^[A-Za-z0-9_-]{6,32}$');

/// One-time codes as the portal accepts them (app/src/lib/requests.ts CODE_PATTERN).
final panelCodePattern = RegExp(r'^[A-Za-z0-9]{6,12}$');

/// The panel's answer is shown as plain text under the field; longer text is cut.
const kCallResultMaxLength = 300;

PanelMessage? parsePanelMessage(dynamic raw) {
  dynamic data = raw;
  if (raw is String) {
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
  if (data is! Map) return null;
  final type = data['type'];
  if (type == 'dolphin-hello') return const PanelMessage('dolphin-hello');
  if (type == 'dolphin-code-request') return const PanelMessage('dolphin-code-request');
  if (type == 'dolphin-call-result') {
    final ok = data['ok'];
    final text = data['text'];
    if (ok is! bool || text is! String || text.trim().isEmpty) return null;
    final t = text.trim();
    return PanelMessage.callResult(ok, t.length > kCallResultMaxLength ? t.substring(0, kCallResultMaxLength) : t);
  }
  final id = data['id'];
  if (type == 'dolphin-connect' && id is String) {
    final clean = id.replaceAll(' ', '');
    if (!panelIdPattern.hasMatch(clean)) return null;
    final code = data['code'];
    if (code == null) return PanelMessage('dolphin-connect', clean);
    if (code is String && panelCodePattern.hasMatch(code)) return PanelMessage('dolphin-connect', clean, code);
    return null;
  }
  return null;
}

/// The panel stays on our portal; any other address is not shown (design 2026-10-27, section 4).
bool isPanelUrl(String url, String portalUrl) =>
    url.isEmpty || url == 'about:blank' || url == portalUrl || url.startsWith('$portalUrl/');

/// The app's answer to the page's hello: its own ID (app/src/lib/app-bridge.ts parseAppMessage).
String idReply(String id) => jsonEncode({'type': 'dolphin-id', 'id': id});

/// The technician app's own field asks the panel to open a call for this ID (WF-2). The panel runs «اتصال».
String callRequest(String id) => jsonEncode({'type': 'dolphin-call', 'id': id});

/// What the field says before it asks the panel; null when the ID can be sent.
String? manualIdProblem(String raw) {
  final id = raw.replaceAll(' ', '');
  if (id.isEmpty) return 'شناسه‌ی مشتری را بنویسید.';
  if (!panelIdPattern.hasMatch(id)) return 'شناسه درست نیست؛ همان عددی را بنویسید که برنامه‌ی مشتری نشان می‌دهد.';
  return null;
}

const kPanelNotReady = 'پنل هنوز باز نشده است؛ چند لحظه صبر کنید و دوباره «اتصال» را بزنید.';
const kPanelChecking = 'در حال بررسی در پنل…';
const kPanelNoAnswer = 'پنل جواب نداد؛ اگر وارد پنل نشده‌اید، اول وارد شوید.';

/// Pushed by the portal (app/src/lib/engine/policy.ts SHOW_CODE_OPTION): "Y" for a PC linked to a code-mode organization.
const kDolphinShowCodeOption = 'dolphin-show-code';

/// The one-time code to show and hand over, or '' when this PC is not in code mode. `approve-mode` alone cannot tell:
/// an unlinked PC also gets "password" (Plan 13 F2), so the portal says it outright.
String dolphinCode({required String approveMode, required String showCode, required String password}) =>
    approveMode == 'password' && showCode == 'Y' && panelCodePattern.hasMatch(password) ? password : '';

/// The customer app's answer to the request form's code request (app/src/lib/app-bridge.ts parseAppMessage).
String codeReply(String code) => jsonEncode({'type': 'dolphin-code', 'code': code});

/// The customer's app answers hello with its ID and, in code mode, a code request with its one-time code. The form
/// asks only when the customer presses «ثبت» (SECURITY.md). It never connects out, whatever the page asks.
String? customerReply(PanelMessage m, String myId, [String myCode = '']) {
  if (m.type == 'dolphin-hello') return panelIdPattern.hasMatch(myId) ? idReply(myId) : null;
  if (m.type == 'dolphin-code-request') return panelCodePattern.hasMatch(myCode) ? codeReply(myCode) : null;
  return null;
}
